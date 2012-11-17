module Prism
  class ServerEvent < Request
    include ChatMessaging
    include Logging
    
    process "server:events", :pinky_id, :server_id, :ts, :type, :msg

    log_tags :world_id, :player_id, :username

    def run
      log = Brain::Logger.new

      if type != 'info'
        log.info event: 'server_event',
          pinky_id: pinky_id,
          server_id: server_id,
          server_ts: ts,
          type: type,
          msg: msg
      end

      case type
      when 'started'
        server_started
      end
    end
    
    def server_started
      redis.get_json("box:#{pinky_id}") do |pinky|
        redis.get_json("pinky:#{pinky_id}:servers:#{server_id}") do |ps|
          redis.publish_json "worlds:requests:start:#{server_id}", {
            host: pinky['ip'],
            port: ps['port']
          }
        end
      end
    end
  end
end