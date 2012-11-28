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

      when 'player_connected'
        player_connected
      when 'player_disconnected'
        player_disconnected
      when 'players_listed'
        players_listed

      when 'settings_changed'
        settings_changed

      when 'fatal_error'
        fatal_error
      end
    end

    def started
      redis.get_json("box:#{pinky_id}") do |pinky|
        redis.get_json("pinky:#{pinky_id}:servers:#{server_id}") do |ps|
          redis.del("server:#{server_id}:restart") do |restarted|
            if restarted > 0
              log.info event: 'restarted_server', server_id: server_id
            end
          end

          redis.publish_json "servers:requests:start:#{server_id}",
            state: 'started',
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
      redis.get "server:#{server_id}:restart" do |restart|
        if restart
          log.info event: 'restarting_server', server_id: server_id
          redis.lpush_hash "servers:requests:start", server_id: server_id
        else
          redis.publish_json "servers:requests:stop:#{server_id}", {}
          Resque.push 'high', class: 'ServerStoppedJob', args: [server_id]
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
      redis.sismember('servers:shared', server_id) do |shared_server|
        if shared_server == 0
          Resque.push 'high',
            class: 'NormalServerTickedJob', args: [server_id, timestamp]

        else
          connected_player_ids(server_id) do |player_ids|
            Resque.push 'high',
              class: 'SharedServerTickedJob', args: [
                server_id, player_ids, timestamp
              ]
          end
        end
      end
    end

    def player_connected
      redis.sadd "server:#{server_id}:players", username
      record_player_metrics
    end

    def player_disconnected
      redis.srem "server:#{server_id}:players", username
      record_player_metrics
    end

    def players_listed
      redis.del "server:#{server_id}:players"
      redis.sadd "server:#{server_id}:players", usernames
      record_player_metrics
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
    def connected_player_ids(server_id, *a, &b)
      cb = EM::Callback(*a, &b)
      redis.hgetall("players:playing") do |players|
        player_ids = players.select {|player_id, player_server_id|
          player_server_id == server_id
        }.keys
        cb.call player_ids
      end
      cb
    end

    def record_player_metrics
      return unless $metrics

      redis.keys 'server:*:players' do |keys|
        EM::Iterator.new(keys, 10).inject(0, proc{|count, key, iter|
          op = redis.scard(key)
          op.callback do |count|
            iter.return(count)
          end
        }, proc{|count|
          Librato::Metrics.submit 'players.count' => {
            :type => :gauge,
            :value => count,
            :source => 'party-cloud'
          }
        })
      end

    end
  end
end