module Prism
  class ServerEvent < Request
    include ChatMessaging
    include Logging

    process "server:events", :pinky_id, :server_id, :server_ts, :type, :msg, :level, :snapshot_id, :url

    log_tags :server_id

    def log
      @log ||= Brain::Logger.new
    end

    def run
      if type != 'info'
        log.info event: 'server_event',
          pinky_id: pinky_id,
          server_id: server_id,
          server_ts: server_ts,
          type: type,
          msg: msg
      end

      case type
      when 'started'
        started

      when 'stopped'
        stopped

      when 'backed_up'
        backed_up
      end
    end

    def started
      redis.get_json("box:#{pinky_id}") do |pinky|
        redis.get_json("pinky:#{pinky_id}:servers:#{server_id}") do |ps|
          redis.publish_json "servers:requests:start:#{server_id}",
            host: pinky['ip'],
            port: ps['port']

          Resque.push 'high', class: 'ServerStartedJob', args: [
            server_id.to_s,
            pinky['ip'],
            ps['port']
          ]
        end
      end
    end

    def stopped
      Resque.push 'high', class: 'ServerStoppedJob', args: [server_id]
    end

    def backed_up
      log.info event: 'backup',
        pinky_id: pinky_id,
        server_id: server_id,
        server_ts: server_ts,
        snapshot_id: snapshot_id,
        url: url
      Resque.push 'high', class: 'ServerBackedUpJob', args: [
        server_id,
        snapshot_id,
        url
      ]
    end
  end
end