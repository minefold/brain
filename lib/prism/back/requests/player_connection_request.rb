# TODO this logic belongs in Minefold, not the Party Cloud

module Prism
  class PlayerConnectionRequest < Request
    include Messaging
    include Logging
    include Back::PlayerConnection
    include ChatMessaging

    process "players:connection_request", :username, :target_host

    log_tags :username

    def kick_player message
      redis.publish_json "players:connection_request:#{username}",
        failed: message
    end

    def whitelisted?(username, settings)
      whitelist = settings['whitelist'] || ''
      ops = settings['ops'] || ''

      (whitelist.split("\n").map{|u| u.strip.downcase } + ops.split("\n").map{|u| u.strip.downcase}).include?(username.downcase)
    end

    def pg
      $pg ||= if ENV['DATABASE_URL']
        url = URI.parse(ENV['DATABASE_URL'])
        PG::Connection.new(
          host:     url.host,
          port:     url.port,
          user:     url.user,
          password: url.password,
          dbname:   url.path[1..-1]
        )
      else
        PG::Connection.new(
          host: 'localhost',
          dbname: 'minefold_development'
        )
      end
    end

    def run
      debug "processing #{username} #{target_host}"

      host = target_host.split(':')[0]

      if host =~ /([\w-]+)\.verify\.minefold\.com/
        verification_request($1)
      else
        connection_request(host)
      end
    end

    def find_server_by_host(host, *a, &b)
      cb = EM::Callback(*a, &b)
      EM.defer(proc {
        results = pg.query(%Q{
            select servers.id,
                   servers.party_cloud_id as server_pc_id,
                   servers.settings,
                   servers.shared,
                   funpacks.party_cloud_id as funpack_pc_id,
                   worlds.party_cloud_id as snapshot_pc_id

            from servers
              inner join funpacks on servers.funpack_id = funpacks.id
               left join worlds on worlds.server_id = servers.id

            where host=$1 and deleted_at is null
            limit 1
          }, [host.downcase])
        results[0] if results.count > 0
      }, cb)
    end

    def find_player_by_username(username, *a, &b)
      cb = EM::Callback(*a, &b)
      EM.defer(proc {
        results = pg.query(%Q{
            select players.id, users.coins from players
              inner join users on users.id = players.user_id
            where players.game_id=$1
              and players.uid=$2
              and users.deleted_at is null
            limit 1
          }, [1, username])
        results[0] if results.count > 0
      }, cb)
    end

    def connection_request(host)
      find_server_by_host(host) do |server|
        if server.nil?
          kick_player "No server found, visit minefold.com"
        else
          valid_server(server)
        end
      end
    end

    def valid_server(server)
      if %w(t 1 true).include?(server['shared'])
        shared_server(server)
      else
        allow_request(server)
      end
    end

    def shared_server(server)
      find_player_by_username(username) do |player|
        if player.nil?
          kick_player "Link your Minecraft account at minefold.com"
        else
          if (player['coins'] || '0').to_i <= 0
            kick_player 'No coins. Get more at minefold.com'
          else
            allow_request(server)
          end
        end
      end
    end

    def allow_request(server)
      @server_id = server['id'].to_i
      server_pc_id = server['server_pc_id']
      settings = JSON.load(server['settings'])
      funpack_pc_id = server['funpack_pc_id']

      if !whitelisted?(username, settings)
        kick_player 'You are not white-listed on this server. Visit minefold.com'

      else
        start_world server_pc_id, funpack_pc_id, settings
      end

    end

    def verification_request(token)
      listen_once "players:verification_request:#{token}" do |response|
        info "verification response:#{response}"
        kick_player response
      end

      Resque.push 'high',
        class: 'LinkMinecraftPlayerJob',
        args: [token, username]
    end

    def start_world server_pc_id, funpack_pc_id, settings
      # if server_pc_id is nil, use a generated reply key until we have a real
      # server_pc_id
      reply_key = (server_pc_id || "req-#{BSON::ObjectId.new}")

      redis.sadd 'servers:shared', server_pc_id

      redis.lpush_hash "servers:requests:start",
        server_id: server_pc_id,
        settings: settings,
        funpack_id: funpack_pc_id,
        reply_key: reply_key

      listen_once_json "servers:requests:start:#{reply_key}", method(:reply_handler)
    end

    def reply_handler reply
      if reply['server_id']
        pg.exec('update servers set party_cloud_id=$1 where id=$2', [reply['server_id'], @server_id])
        redis.sadd 'servers:shared', reply['server_id']
      end

      case reply['state']
      when 'starting'
        # start listening on the real server_id rather than generated reply key
        EM.next_tick do
          listen_once_json "servers:requests:start:#{reply['server_id']}", method(:reply_handler)
        end

      when 'started'
        connect_player_to_server @player_id, reply['server_id'], reply['host'], reply['port']

      else
        kick_player reply['failed']
      end
    end

    def connect_player_to_server player_id, server_id, host, port
      info "connecting to #{host}:#{port}"

      # this tells prism to connect the player to the server
      redis.publish_json "players:connection_request:#{username}",
        host: host,
        port: port,
        player_id: player_id,
        world_id: server_id
    end
  end
end
