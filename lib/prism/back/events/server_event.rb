require 'core_ext/hash'
require 'core_ext/string'
require 'tron'

module Prism
  class ServerEvent < Request
    include ChatMessaging
    include Logging

    process "server:events",
      :pinky_id,
      :server_id,
      :ts,            # server timestamp
      :level,         # level (info|warn|error)
      :type,          # event type
      :msg,           # msg (chat)

      # backups
      :snapshot_id,
      :url,

      # user accounts
      :auth,
      :uid,
      :uids,
      :nick,

      # settings changed
      :actor,
      :add,
      :remove,
      :set,
      :value,

      # deprecated
      :key,
      :username,
      :usernames


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
        data.merge_val(:auth, auth)
        data.merge_val(:uid, uid)
        data.merge_val(:uids, uids)
        data.merge_val(:nick, nick)
        data.merge_val(:username, username)
        data.merge_val(:usernames, usernames)
        data.merge_val(:actor, actor)
        data.merge_val(:set, set)
        data.merge_val(:add, add)
        data.merge_val(:remove, remove)
        data.merge_val(:key, key)
        data.merge_val(:value, value)
        data.merge_val(:ip, value)
        data.merge_val(:at, value)

        log.info data
      end

      case type
      when 'started'
        started

      when 'stopping'
        # TODO: stopping state disabled because restart doesn't work yet
        # restarting doesn't work because the servers settings aren't being
        # read back out of mongo when they aren't provided in the start server
        # request
        stopping

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
            msg = {
              at: Time.now.to_i,
              ip: pinky['ip'],
              port: ps['port'],
              state: 'started',
              host: pinky['ip']
            }
            redis.publish_json "servers:requests:start:#{server_id}", msg

            Models::Server.update(
              { _id: BSON::ObjectId(server_id) },
              { '$set' => { host: "#{pinky['ip']}:#{ps['port']}" } }
            ) do
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
    end

    def start_failed
      log.info event: 'start_failed', server: server_id
      redis.del("server:#{server_id}:restart")
      redis.del("server:#{server_id}:state")

      redis.publish_json "servers:requests:start:#{server_id}",
        failed: 'Server failed to start. Please contact support'
      Resque.push 'high', class: 'ServerStoppedJob', args: [Time.now.to_i, server_id]
    end

    def stopping
      redis.set("server:#{server_id}:state", "stopping")
    end

    def stopped
      redis.get "server:#{server_id}:state" do |state|
        redis.del("server:#{server_id}:state")
        redis.del("server:#{server_id}:players")
        redis.del("server:#{server_id}:slots")
        redis.del("server:#{server_id}:funpack")

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
                Time.parse(ts).to_i, server_id
              ]
              
              Tron.server_stopped server_id, Time.now
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
      timestamp = Time.parse(ts).to_i
      connected_player_usernames(server_id) do |usernames|
        Resque.push 'high', class: 'SharedServerTickedJob',
          args: [server_id, usernames, timestamp]
      end
    end

    def player_connected
      timestamp = Time.parse(ts).to_i
      redis.sadd "server:#{server_id}:players", (uid || username)

      Resque.push 'high', class: 'PlayerConnectedJob',
        args: [timestamp, server_id, (uid || username)]
    end

    def player_disconnected
      redis.srem "server:#{server_id}:players", (uid || username)

      timestamp = Time.parse(ts).to_i
      Resque.push 'high', class: 'PlayerDisconnectedJob',
        args: [timestamp, server_id, (uid || username)]
    end

    def players_list
      redis.setex "server:#{server_id}:heartbeat", 5*60, 1
      redis.del "server:#{server_id}:players"
      (uids || usernames || []).each do |username|
        redis.sadd "server:#{server_id}:players", username
      end
    end

    def settings_changed
      transform = case
      when key =~ /([a-z]+)_add/      # TODO deprecate
        { add: $1 }
      when key =~ /([a-z]+)_remove/   # TODO deprecate
        { remove: $1 }
      when !key.blank?                # TODO deprecate
        { set: key }
      when !add.blank?
        { add: add }
      when !remove.blank?
        { remove: remove }
      when !set.blank?
        { set: set }
      end

      if transform
        Resque.push 'low',
          class: 'ServerSettingsChangedJob',
           args: [Time.now.to_i, server_id, transform.merge(actor: actor, value: value)]
      end
    end

    def fatal_error
      redis.get "server:#{server_id}:state" do |state|
        puts "SERVER STATE: #{state}"
      end

      redis.publish "servers:requests:start:#{server_id}",
        JSON.dump(failed: 'server error')
    end

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
