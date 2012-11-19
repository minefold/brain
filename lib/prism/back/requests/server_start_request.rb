module Prism
  class ServerStartRequest < Request
    include Logging
    include Messaging

    process "worlds:requests:start", :server_id, :world_id, :settings, :funpack_id, :player_slots

    attr_reader :server_id, :world_id, :settings, :funpack_id

    log_tags :server_id

    def reply options = {}
      redis.publish_json "worlds:requests:start:#{server_id}", options
    end

    def run
      redis.get "server:#{server_id}:state" do |state|
        case state
        when 'up'
          debug "world:#{server_id} is already running"
          reply world

        when 'starting'
          debug "world:#{server_id} start already requested"

        when 'stopping'
          # TODO
          debug "world:#{server_id} is stopping. will request start when stopped"

        else
          debug "world:#{server_id} is not running"
          start_world
        end
      end
    end

    def start_world
      debug "getting world:#{server_id} started"

      redis.set "server:#{server_id}:state", "starting"

      World.find(server_id) do |world|
        if world.nil?
          reply failed: 'no_world'
        else
          slots_required = player_slots || world.allocation_slots
          Pinkies.collect do |pinkies|
            allocator = Allocator.new(pinkies)
            start_options = allocator.start_options_for_new_world(slots_required)

            if start_options and start_options[:pinky_id]
              start_with_settings world, start_options

            else
              info "no instances available"
              reply failed:'no_instances_available'
            end
          end
        end
      end
    end

    def start_with_settings world, start_options
      # TODO store in database
      funpacks = {
        '50a976ec7aae5741bb000001' => 'https://minefold-production.s3.amazonaws.com/funpacks/slugs/minecraft-vanilla/1.tar.lzo',
        '50a976fb7aae5741bb000002' => 'https://minefold-production.s3.amazonaws.com/funpacks/slugs/minecraft-essentials/1.tar.lzo',
        '50a977097aae5741bb000003' => 'https://minefold-production.s3.amazonaws.com/funpacks/slugs/minecraft-tekkit/1.tar.lzo',
      }
      
      funpack = funpacks[funpack_id]
      
      if funpack.nil?
        reply failed: "No funpack found for #{funpack_id}"

      else
        start_options.merge!(
          'serverId' => server_id,
          'funpack' => funpack,
          'settings' => settings
        )

        if world.world_data_file
          start_options['world'] = world.world_data_file
        end

        debug "start options: #{start_options}"

        pinky_id = start_options[:pinky_id]
        debug "starting world:#{server_id} on pinky:#{pinky_id} heap:#{start_options[:heap_size]}"

        start_options['name'] = 'start'

        redis.lpush_hash "pinky:#{pinky_id}:in", start_options
      end
    end
  end
end