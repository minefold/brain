module Prism
  class ServerRestartRequest < Request
    include Messaging
    include ChatMessaging
    include Logging

    process "servers:requests:restart", :server_id, :settings, :funpack_id, :reply_key, :message

    def run
      info "restarting server:#{server_id} message:#{message}"
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
      EM.add_timer(10) do
        server_broadcast @pinky_id, server_id, message
        EM.add_timer(2) do
          cb.call
        end
      end
      cb
    end

    def restart_server
      redis.set "server:#{server_id}:restart", 1
      redis.lpush "servers:requests:stop", server_id
    end
  end
end