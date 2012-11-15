module Prism
  class WorldStartRequest < Request
    include Logging
    include Messaging

    process "worlds:requests:start", :world_id, :player_slots

    attr_reader :world_id

    log_tags :world_id

    def reply options = {}
      redis.publish_json "worlds:requests:start:#{world_id}", options
    end

    def run
      redis.get "server:#{world_id}:state" do |state|
        case state
        when 'up'
          debug "world:#{world_id} is already running"
          reply world

        when 'starting'
          debug "world:#{world_id} start already requested"

        when 'stopping'
          # TODO
          debug "world:#{world_id} is stopping. will request start when stopped"
          # redis.set_busy "worlds:busy", world_id, 'stopping => starting', expires_after: 120
          # listen_once "worlds:requests:stop:#{world_id}" do
          #   debug "world:#{world_id} stopped. Requesting restart"
          #   start_world
          # end

        else
          debug "world:#{world_id} is not running"
          start_world
        end
      end
    end

    def start_world
      debug "getting world:#{world_id} started"
      
      redis.set "server:#{world_id}:state", "starting"

      World.find(world_id) do |world|
        if world.nil?
          reply failed: 'no_world'
        else
          slots_required = player_slots || world.allocation_slots
          Pinkies.collect do |pinkies|
            allocator = Allocator.new(pinkies)
            start_options = allocator.start_options_for_new_world(slots_required)

            if start_options and start_options[:pinky_id]
              add_server_settings world, start_options

            else
              info "no instances available"
              reply failed:'no_instances_available'
            end
          end
        end
      end
    end

    def add_server_settings world, start_options
      opped_player_ids = Array(world.opped_player_ids)
      whitelisted_player_ids = Array(world.whitelisted_player_ids)
      banned_player_ids = Array(world.banned_player_ids)

      world_player_ids = opped_player_ids | whitelisted_player_ids | banned_player_ids

      puts "searching:#{world_player_ids}"

      MinecraftPlayer.find_all(deleted_at: nil, _id: {'$in' => world_player_ids}) do |world_players|

        puts "found:#{world_players}"
        opped_players = world_players.select{|p| opped_player_ids.include?(p.id)}
        whitelisted_players = world_players.select{|p| whitelisted_player_ids.include?(p.id)}
        banned_players = world_players.select{|p| banned_player_ids.include?(p.id)}

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

        start_options.merge!(
          'serverId' => world_id,
          'funpack' => 'https://minefold-production.s3.amazonaws.com/funpacks/slugs/minecraft-vanilla/1.tar.lzo',
          'world' => "https://minefold-development.s3.amazonaws.com/worlds/#{world.world_data_file}",
          'settings' => {
            'ops' => (opped_players.map(&:username) | World::DEFAULT_OPS).uniq,
            'whitelisted' => whitelisted_players.map(&:username).uniq,
            'banned' => banned_players.map(&:username).uniq,
          }
        )

        start_options['settings'].merge!(
          world_settings.each_with_object({}){|setting, h| h[setting] = world.doc[setting] }
        )
        debug "start options: #{start_options}"

        start_world_with_options start_options
      end
    end

    def start_world_with_options options
      pinky_id = options[:pinky_id]
      debug "starting world:#{world_id} on pinky:#{pinky_id} heap:#{options[:heap_size]}"

      options['name'] = 'start'

      redis.lpush_hash "pinky:#{pinky_id}:in", options
    end
  end
end