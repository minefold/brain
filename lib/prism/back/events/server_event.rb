module Prism
  class ServerEvent < Request
    include ChatMessaging
    include Logging

    process "server:events", :pinky_id, :server_id, :ts, :type, :msg, :level, :snapshot_id, :url

    log_tags :server_id

    def log
      @log ||= Brain::Logger.new
    end

    def run
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
        started

      when 'stopped'
        stopped

      when 'backed_up'
        backed_up

      when 'minute'
        minute
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
      Resque.push 'high', class: 'ServerBackedUpJob', args: [
        server_id,
        snapshot_id,
        url
      ]
    end

    def minute
      # TODO this logic belongs in Minefold, not Party Cloud

      timestamp = Time.parse(ts).to_i
      redis.sismember('servers:shared', server_id) do |shared_server|
        if shared_server == 0
          Resque.push 'high',
            class: 'NormalServerTickedJob', args: [server_id, timestamp]

        else
          redis.hgetall("players:playing") do |players|
            player_ids = players.select {|player_id, player_server_id|
              player_server_id == server_id
            }.keys
            
          Resque.push 'high',
            class: 'SharedServerTickedJob', args: [
              server_id, player_ids, timestamp
            ]
          end

        end
      end
    end
  end
end