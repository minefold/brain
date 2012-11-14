module Prism
  class PlayerConnectedEvent < Request
    include ChatMessaging
    include Logging

    process "player:connected", :session_id, :world_id, :player_id, :username, :timestamp

    log_tags :session_id, :world_id, :player_id, :username

    def run
      MinecraftPlayer.find_with_user(player_id) do |player|
        raise "unknown player:#{player_id}" unless player

        player.update('$set' => { last_connected_at: Time.now })
        
        Session.insert(
          {        _id: BSON::ObjectId(session_id),
             player_id: BSON::ObjectId(player_id),
              world_id: BSON::ObjectId(world_id),
              started_at: Time.at(timestamp),
          }
        )

        redis.hget_json "worlds:running", world_id do |world|
          if world
            @instance_id = world['instance_id']
            World.find(world_id) do |world|
              send_welcome_messages world
            end
          else
            warn "world not running?"
          end
        end
      end
    end

    def current_players *a, &b
      cb = EM::Callback(*a, &b)
      op = redis.hgetall "players:playing"
      op.callback do |players|
        cb.call players.select {|username, player_world_id| player_world_id == world_id }.keys
      end
      cb
    end

    def friends_message *a, &b
      cb = EM::Callback *a, &b
      current_players do |players|
        cb.call players.size == 1 ?
          "It's just you, invite some friends!" :
          "There #{players.size == 2 ? 'is' : 'are'} #{pluralize (players.size - 1), "other player"} in this world"
      end
      cb
    end

    def send_welcome_messages world
      EM.add_timer(2) do
        friends_message do |message|
          send_delayed_message 0,
            "Welcome to minefold.com!",
             "You're playing in #{world.name}"
          send_delayed_message 1, message
        end
      end
    end
  end
end