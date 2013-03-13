module Prism
  class ServerStartRequest < Request
    include Logging
    include Messaging

    MESSAGES = {
      server_not_found: 'Unknown server. Check minefold.com for correct address',
      no_instances_available: 'Minefold is under heavy load! Please try again',
      no_funpack_found: 'No funpack found for server. Contact support@minefold.com',
    }

    process "servers:requests:start",
      :server_id, :funpack_id, :reply_key, :data

    attr_reader :server_id, :funpack_id

    log_tags :server_id

    def reply(state, args = {})
      args[:message] = MESSAGES[args[:reason].to_sym] if args[:reason]

      if state == 'failed'
        Scrolls.log(
          at: 'server_start_request',
          failed: args[:reason],
          message: args[:message],
          server_id: server_id
        )

        redis.lpush_hash 'server:events', server_id: server_id, failed: args[:reason]
      end

      puts "replying servers:requests:start:#{reply_key} #{args.merge(state: state)}"
      redis.publish_json "servers:requests:start:#{reply_key}",
        args.merge(state: state)
    end

    def run
      Scrolls.log({
        at: 'servers:requests:start',
        server_id: server_id,
        funpack_id: funpack_id,
        data: data,
        reply_key: reply_key
      })

      if server_id.nil?
        reply 'failed', reason: 'server_not_found'
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
                    if pinky
                      reply 'started',
                        server_id: server_id,
                        host: pinky['ip'],
                        port: ps['port']
                    else
                      reply 'failed', failed: 'Connection failed. Please try again'
                    end
                  end
                end
              else
                reply 'failed', failed: 'Connection failed. Please try again'
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

      Scrolls.log(
        at: 'starting server',
        server_id: server_id,
        funpack_id: funpack_id
      )

      Models::Server.upsert(server_id, funpack_id, data) do |server|
        # funpack_id ||= server.funpack_id

        Scrolls.log(
          at: 'updated server',
          server_id: server_id,
          funpack_id: funpack_id
        )

        data ||= server.settings

        slots_required = server.slots || 1

        # TODO hack to give FTB 2 slots
        if funpack_id == '512159a67aae57bf17000005'
          slots_required = [2, slots_required].max
        end

        Pinkies.collect do |pinkies|
          allocator = Allocator.new(pinkies)
          start_options = allocator.start_options_for_new_server(slots_required)

          if start_options and start_options[:pinky_id]
            start_with_settings (server.new_snapshot_id || server.snapshot_id),
              data,
              funpack_id,
              start_options

          else
            redis.del "server:#{server_id}:state"
            reply 'failed', reason: 'no_instances_available'
          end
        end
      end
    end

    def start_with_settings(snapshot_id, data, funpack_id, start_options)
      funpack = Funpack.find(funpack_id)

      if funpack.nil?
        reply 'failed', reason: 'no_funpack_found'

      else
        start_options.merge!(
          'serverId' => server_id,
          'funpack' => funpack.url,
          'funpackId' => funpack_id,
          'funpackUrl' => funpack.url,
          'data' => data
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

    def start_server(start_options)
      Models::Server.update(
        { _id: BSON::ObjectId(server_id) },
        { '$unset' => { new_snapshot_id: nil } }
      ) do
        start_options['name'] = 'start'
        debug "start options: #{start_options}"

        redis.set "server:#{server_id}:funpack", start_options['funpackId']
        redis.set "server:#{server_id}:slots", start_options[:slots]
        redis.lpush_hash "pinky:#{start_options[:pinky_id]}:in", start_options
      end
    end
  end
end