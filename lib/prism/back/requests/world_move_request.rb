module Prism
  class WorldMoveRequest < Request
    include Messaging
    include ChatMessaging
    include Logging
    
    process "worlds:move_request", :world_id, :player_slots

    # this is the process
    # 1. message gamers that the world is about to die
    # 2. restart world
    # 3. email players?

    def run
      info "moving world:#{world_id} to player_slots:#{player_slots}"
      redis.setex "worlds:#{world_id}:moving", 300, Time.now.to_i

      redis.hget_json 'worlds:running', world_id do |world|
        if world
          @instance_id = world['instance_id']

          message_gamers do
            restart_world
          end
        end
      end
    end

    def message_gamers *a, &b
      cb = EM::Callback *a, &b
      send_world_message @instance_id, world_id, "Optimizing server: restart required"
      EM.add_timer(2) do
        send_world_message @instance_id, world_id, "Please reconnect in 30 seconds"
        EM.add_timer(8) do
          op = redis.hgetall "players:playing"
          op.callback do |players|
            users = players.select{|username, player_world_id| player_world_id == world_id }.keys
            users.each do |username|
              redis.publish "players:disconnect:#{username}", "Please reconnect in 30 seconds"
            end
            cb.call
          end
        end
      end
      cb
    end

    def restart_world
      redis.lpush "workers:#{@instance_id}:worlds:requests:stop", world_id

      # TODO: there's a half second gap here!
      EM.add_timer(0.5) do
        redis.lpush_hash "worlds:requests:start", world_id: world_id, player_slots: player_slots
      end
    end
  end
end