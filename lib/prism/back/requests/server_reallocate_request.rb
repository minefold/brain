module Prism
  class ServerReallocateRequest < Request
    include Messaging
    include ChatMessaging
    include Logging

    process "servers:reallocate_request", :server_id, :slots, :message

    # this is the process
    # 1. message gamers that the world is about to die
    # 2. restart world
    # 3. email players?

    def run
      info "reallocating server:#{server_id} to slots:#{slots}"
      redis.get "server:#{server_id}:state" do |state|
        if state == 'up'
          redis.keys("pinky:*:servers:#{server_id}") do |keys|
            if key = keys.first
              @pinky_id = key.split(':')[1]
              message_players do
                restart_server
              end
            end
          end
        end
      end
    end

    def message_players *a, &b
      cb = EM::Callback *a, &b
      server_broadcast @pinky_id, server_id, message
      EM.add_timer(5) do
        server_broadcast @pinky_id, server_id, message
        cb.call
      end
      cb
    end

    def restart_server
      Models::Server.update(
        { _id: BSON::ObjectId(server_id) },
        { '$set' => { slots: slots } }
      ) do
        redis.set "server:#{server_id}:restart", 1
        redis.lpush "servers:requests:stop", server_id
      end
    end
  end
end