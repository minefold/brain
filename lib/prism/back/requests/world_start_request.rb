module Prism
  class WorldStartRequest < Request
    include Logging
    include Messaging

    process "worlds:requests:start", :world_id, :player_slots

    attr_reader :instance_id

    log_tags :world_id

    def reply options = {}
      redis.publish_json "worlds:requests:start:#{world_id}", options
    end

    def run
      state = redis.get "server/state/#{world_id}"
      case state
      when 'up'
        debug "world:#{world_id} is already running"
        reply world

      when 'starting'
        debug "world:#{world_id} start already requested"
        respond_to_world_start_event

      when 'stopping'
        debug "world:#{world_id} is stopping. will request start when stopped"
        redis.set_busy "worlds:busy", world_id, 'stopping => starting', expires_after: 120
        listen_once "worlds:requests:stop:#{world_id}" do
          debug "world:#{world_id} stopped. Requesting restart"
          start_world
        end

      else
        debug "world:#{world_id} is not running"
        start_world
      end
    end

    def start_world
      debug "getting world:#{world_id} started"

      World.find(world_id) do |world|
        if world.nil?
          reply failed: 'no_world'
        else
          slots_required = player_slots || world.allocation_slots
          Pinkies.collect do |pinkies|
            allocator = Allocator.new(pinkies)
            start_options = allocator.start_options_for_new_world(slots_required)
            if start_options and start_options[:instance_id]
              add_start_options_for_world world, start_options
            else
              info "no instances available"
              reply failed:'no_instances_available'
            end
          end
        end
      end

      # Prism::RedisUniverse.collect do |universe|
      #   World.find(world_id) do |world|
      #     if world
      #       slots_required = player_slots || world.allocation_slots
      # 
      #       start_options = WorldAllocator.new(universe).start_options_for_new_world world.doc, slots_required
      # 
      #       if start_options and start_options[:instance_id]
      #         add_start_options_for_world world, start_options
      #       else
      #         info "no instances available"
      #         reply failed:'no_instances_available'
      #       end
      #     else
      #       reply failed:'no_world'
      #     end
      #   end
      # end
    end

    def add_start_options_for_world world, start_options
      opped_player_ids = Array(world.opped_player_ids)
      whitelisted_player_ids = Array(world.whitelisted_player_ids)
      banned_player_ids = Array(world.banned_player_ids)

      world_player_ids = opped_player_ids | whitelisted_player_ids | banned_player_ids

      MinecraftPlayer.find_all(deleted_at: nil, _id: {'$in' => world_player_ids}) do |world_players|
        opped_players = world_players.select{|p| opped_player_ids.include?(p.id)}
        whitelisted_players = world_players.select{|p| whitelisted_player_ids.include?(p.id)}
        banned_players = world_players.select{|p| banned_player_ids.include?(p.id)}

        funpack_defaults = {
                   name: world.funpack || 'minecraft-vanilla',
                   # name: 'Minecraft',
                version: '1.0',

              data_file: world.world_data_file,
                    ops: (opped_players.map(&:username) | World::DEFAULT_OPS).compact,
            whitelisted: whitelisted_players.map(&:username).compact,
                 banned: banned_players.map(&:username).compact
        }
        world_settings = %w(
          minecraft_version
          seed
          level_type
          online_mode
          difficulty
          game_mode
          pvp
          spawn_animals
          spawn_monsters)

        pack_settings = funpack_defaults.merge(world_settings.each_with_object({}){|setting, h| h[setting] = world.doc[setting] })

        start_options.merge! world_id: world_id, funpack: pack_settings

        debug "start options: #{start_options}"

        start_world_with_options start_options
      end
    end

    def start_world_with_options options
      instance_id = options[:instance_id]
      debug "starting world:#{world_id} on worker:#{instance_id} heap:#{options[:heap_size]}"

      redis.set_busy "worlds:busy", world_id, 'starting', expires_after: 600
      redis.lpush_hash "workers:#{instance_id}:worlds:requests:start", options

      respond_to_world_start_event
    end

    def respond_to_world_start_event
      listen_once_json "worlds:requests:start:#{world_id}" do |world|
        redis.hdel "worlds:busy", world_id

        if world['failed']
          Exceptional.rescue { raise "World start failed: #{world['failed']}" }
          reply failed:'500'
        else
          debug "world started"
          reply world
        end
      end
    end
  end
end