module Prism
  class PlayerWorldRequest < Request
    include Messaging
    include ChatMessaging
    include Logging
    include Back::PlayerConnection

    process "players:world_request", :username, :player_id, :world_id, :description

    log_tags :player_id, :world_id

    attr_reader :instance_id

    def run
      redis.get "server:#{world_id}:state" do |state|
        if state == 'up'
          redis.get_json("box:#{pinky_id}") do |pinky|
            redis.get_json("pinky:#{pinky_id}:servers:#{server_id}") do |ps|
              redis.publish_json "worlds:requests:start:#{server_id}", {
                host: pinky['ip'],
                port: ps['port']
              }
            end
          end
          
          connect_player_to_world world['host'], world['port']
        else
          start_world
        end
      end
    end

    def start_world
      debug "world:#{world_id} is not running"
      redis.lpush_hash "worlds:requests:start", world_id: world_id
      listen_once_json "worlds:requests:start:#{world_id}" do |world|
        if world['host']
          connect_player_to_world world['host'], world['port']
        else
          reject_player username, world['failed']
        end
      end
    end


    def connect_player_to_world host, port
      info "connecting to #{host}:#{port}"
      redis.publish_json "players:connection_request:#{username}", host:host, port:port, player_id:player_id, world_id:world_id
    end
  end
end