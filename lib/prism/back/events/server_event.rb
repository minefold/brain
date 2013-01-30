require 'core_ext/hash'

module Prism
  class ServerEvent < Request
    include ChatMessaging
    include Logging

    process "server:events", :pinky_id, :server_id, :ts, :type, :msg, :level, :snapshot_id, :url, :username, :usernames, :actor, :key, :value

    log_tags :server_id

    def log
      @log ||= Brain::Logger.new
    end

    def run
      if type != 'info'
        data = {
          event: 'server_event',
          pinky_id: pinky_id,
          server_id: server_id,
          server_ts: ts,
          type: type
        }

        data.merge_val(:msg, msg)
        data.merge_val(:snapshot_id, snapshot_id)
        data.merge_val(:url, url)
        data.merge_val(:username, username)
        data.merge_val(:usernames, usernames)
        data.merge_val(:actor, actor)
        data.merge_val(:key, key)
        data.merge_val(:value, value)

        log.info data
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

      when 'player_connected'
        player_connected
      when 'player_disconnected'
        player_disconnected

      when 'players_list'
        players_list

      when 'settings_changed'
        settings_changed

      when 'fatal_error'
        fatal_error
      end
    end

    def started
      redis.get_json("box:#{pinky_id}") do |pinky|
        redis.get_json("pinky:#{pinky_id}:servers:#{server_id}") do |ps|
          redis.set("server:#{server_id}:state", "up")

          redis.del("server:#{server_id}:restart") do |restarted|
            if restarted > 0
              log.info event: 'restarted_server', server_id: server_id
            end
          end

          if pinky and ps
            redis.publish_json "servers:requests:start:#{server_id}",
              state: 'started',
              host: pinky['ip'],
              port: ps['port']

            Resque.push 'high', class: 'ServerStartedJob', args: [
              server_id.to_s,
              pinky['ip'],
              ps['port'],
              Time.parse(ts).to_i
            ]
          end
        end
      end
    end

    def start_failed
      log.info event: 'start_failed', server: server_id
      redis.del("server:#{server_id}:restart")
      redis.del("server:#{server_id}:state")

      redis.publish_json "servers:requests:start:#{server_id}",
        failed: 'Server failed to start. Please contact support'
      Resque.push 'high', class: 'ServerStoppedJob', args: [Time.now.to_i, server_id]
    end

    def stopped
      redis.get "server:#{server_id}:state" do |state|
        redis.del("server:#{server_id}:state")
        redis.del("server:#{server_id}:players")
        redis.del("server:#{server_id}:slots")

        if state == 'starting'
          start_failed
        else
          redis.get "server:#{server_id}:restart" do |restart|
            if restart
              log.info event: 'restarting_server', server_id: server_id
              redis.lpush_hash "servers:requests:start", server_id: server_id
            else
              redis.publish_json "servers:requests:stop:#{server_id}", {}
              Resque.push 'high', class: 'ServerStoppedJob', args: [
                Time.parse(ts).to_i, server_id]
            end
          end
        end
      end
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
      connected_player_usernames(server_id) do |usernames|
        Resque.push 'high', class: 'SharedServerTickedJob',
          args: [server_id, usernames, timestamp]
      end
    end

    def player_connected
      timestamp = Time.parse(ts).to_i
      redis.sadd "server:#{server_id}:players", username

      Resque.push 'high', class: 'PlayerConnectedJob',
        args: [timestamp, server_id, username]
    end

    def player_disconnected
      redis.srem "server:#{server_id}:players", username

      timestamp = Time.parse(ts).to_i
      Resque.push 'high', class: 'PlayerDisconnectedJob',
        args: [timestamp, server_id, username]
    end

    def players_list
      redis.setex "server:#{server_id}:heartbeat", 5*60, 1
      redis.del "server:#{server_id}:players"
      (usernames || []).each do |username|
        redis.sadd "server:#{server_id}:players", username
      end
    end

    def settings_changed
      Resque.push 'high',
        class: 'ServerSettingsChangedJob',
         args: [server_id, {
           setting: key,
           value: value,
           actor: actor
         }]
    end

    def fatal_error
      # TODO this logic belongs in Minefold, not Party Cloud
      redis.get "server:#{server_id}:state" do |state|
        puts "SERVER STATE: #{state}"
      end

      redis.publish "servers:requests:start:#{server_id}",
        JSON.dump(failed: 'server error')
    end

    # TODO this logic belongs in Minefold, not Party Cloud
    def connected_player_usernames(server_id, *a, &b)
      cb = EM::Callback(*a, &b)
      op = redis.smembers("server:#{server_id}:players")
      op.callback do |usernames|
        cb.call usernames
      end
      cb
    end
  end
end
