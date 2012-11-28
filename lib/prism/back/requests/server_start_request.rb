module Prism
  class ServerStartRequest < Request
    include Logging
    include Messaging

    process "servers:requests:start",
      :server_id, :settings, :funpack_id, :reply_key

    attr_reader :server_id, :server_id, :settings, :funpack_id

    log_tags :server_id

    def reply state, args = {}
      puts "replying servers:requests:start:#{reply_key} #{args.merge(state: state)}"
      redis.publish_json "servers:requests:start:#{reply_key}",
        args.merge(state: state)
    end

    def run
      if server_id.nil?
        reply 'failed', reason: 'server not found'
      else
        redis.get "server:#{server_id}:state" do |state|
          case state
          when 'up'
            debug "server:#{server_id} is already running"
            redis.keys("pinky:*:servers:#{server_id}") do |keys|
              if key = keys.first
                pinky_id = key.split(':')[1]
                redis.get_json("box:#{pinky_id}") do |pinky|
                  redis.get_json("pinky:#{pinky_id}:servers:#{server_id}") do |ps|
                    reply 'started',
                      server_id: server_id,
                      host: pinky['ip'],
                      port: ps['port']
                  end
                end
              else
                reply 'failed', reason: '500'
              end
            end

          when 'starting'
            debug "server:#{server_id} start already requested"

          when 'stopping'
            debug "server:#{server_id} is stopping. will request start when stopped"
            redis.set "server:#{server_id}:restart", 1

          else
            debug "server:#{server_id} is not running"
            find_and_start_server
          end
        end
      end
    end

    def find_and_start_server
      redis.set "server:#{server_id}:state", "starting"

      reply 'starting', server_id: server_id

      Models::Server.upsert(server_id, funpack_id, settings) do |server|
        slots_required = server.slots || 1

        Pinkies.collect do |pinkies|
          allocator = Allocator.new(pinkies)
          start_options = allocator.start_options_for_new_server(slots_required)

          if start_options and start_options[:pinky_id]
            start_with_settings server.snapshot_id,
              server.settings,
              server.funpack_id,
              start_options

          else
            reply 'failed', reason: 'no_instances_available'
          end
        end
      end
    end

    def start_with_settings snapshot_id, settings, funpack_id, start_options
      # TODO store in database
      funpacks = {
        '50a976ec7aae5741bb000001' => 'https://party-cloud-production.s3.amazonaws.com/funpacks/slugs/minecraft-vanilla/1.tar.lzo',
        '50a976fb7aae5741bb000002' => 'https://party-cloud-production.s3.amazonaws.com/funpacks/slugs/minecraft-essentials/1.tar.lzo',
        '50a977097aae5741bb000003' => 'https://party-cloud-production.s3.amazonaws.com/funpacks/slugs/minecraft-tekkit/1.tar.lzo',
      }

      funpack = funpacks[funpack_id]

      if funpack.nil?
        reply 'failed', reason: "No funpack found for #{funpack_id}"

      else
        start_options.merge!(
          'serverId' => server_id,
          'funpack' => funpack,
          'settings' => settings
        )

        if snapshot_id.nil?
          start_server start_options
        else
          Models::Snapshot.find(snapshot_id) do |snapshot|
            if snapshot
              start_options['worldUrl'] = snapshot.url
            end

            start_server start_options
          end
        end
      end
    end

    def start_server start_options
      start_options['name'] = 'start'
      debug "start options: #{start_options}"

      redis.set "server:#{server_id}:slots", start_options[:slots]
      redis.lpush_hash "pinky:#{start_options[:pinky_id]}:in", start_options
    end
  end
end