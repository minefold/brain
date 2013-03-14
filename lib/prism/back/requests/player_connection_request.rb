# TODO this logic belongs in Minefold, not the Party Cloud

module Prism
  class PlayerConnectionRequest < Request
    include Messaging
    include Logging
    include Back::PlayerConnection
    include ChatMessaging

    process "players:connection_request", :client, :client_address, :version, :username, :target_host, :reply_key

    log_tags :username

    def log(opts)
      Scrolls.log({
        username: username,
        host: target_host,
        version: version}.merge(opts))
    end

    def kick_player(message)
      log(kick: message)

      # TODO new prism will always send reply_key
      if reply_key
        redis.publish_json reply_key,
          failed: message
      else
        redis.publish_json "players:connection_request:#{username}",
          failed: message
      end
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
      host = target_host.split(':')[0]

      if host =~ /([\w-]+)\.verify\.minefold\.com/i
        verification_request($1)
      else
        connection_request(host.downcase)
      end
    end

    def find_server_by_host(host, *a, &b)
      cb = EM::Callback(*a, &b)

      query = if host =~ /(\w+)\.fun-(\w+)\.([\w-]+)\.foldserver\.com/
        log(lookup: 'dynamic', id: $1)
        ['servers.id=$1', $1.to_i]
      else
        log(lookup: 'cname', host: host)
        ['servers.cname=$1', host]
      end

      EM.defer(proc {
        results = pg.query(%Q{
            select servers.id,
                   servers.name,
                   servers.party_cloud_id as server_pc_id,
                   servers.settings,
                   servers.shared,
                   servers.access_policy_id,
                   funpacks.party_cloud_id as funpack_pc_id,
                   worlds.party_cloud_id as snapshot_pc_id,
                   users.coins as creator_coins,
                   users.username as creator_username

            from servers
              inner join funpacks on servers.funpack_id = funpacks.id
               left join worlds on worlds.server_id = servers.id
              inner join users on servers.creator_id = users.id

            where #{query[0]} and servers.deleted_at is null
            limit 1
          }, [query[1]])
        results[0] if results.count > 0
      }, cb)
    end

    def find_player_by_username(username, *a, &b)
      cb = EM::Callback(*a, &b)
      EM.defer(proc {
        results = pg.query(%Q{
            select accounts.id, users.coins from accounts
              inner join users on users.id = accounts.user_id
            where accounts.type = 'Accounts::Mojang'
              and accounts.uid=$1
              and users.deleted_at is null
            limit 1
          }, [username])
        results[0] if results.count > 0
      }, cb)
    end

    def connection_request(host)
      find_server_by_host(host) do |server|
        if server.nil?
          kick_player "No server found, visit minefold.com"
        else
          server['settings'] ||= {}
          valid_client(server)
        end
      end
    end

    def valid_client(server)
      funpack = Funpack.find(server['funpack_pc_id'])
      if funpack == '' || funpack.nil?
        kick_player "Bad funpack. Contact support@minefold.com"
      else
        if funpack.client_version && funpack.client_version != version
          kick_player funpack.bump_message
        else
          valid_server(server)
        end
      end
    end

    def valid_server(server)
      if %w(t 1 true).include?(server['shared'])
        shared_server(server)
      else
        normal_server(server)
      end
    end

    def normal_server(server)
      if (server['creator_coins'] || '0').to_i <= 0
        kick_player "#{server['creator_username']} is out of time. Bug them!"
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
            kick_player 'Out of time! Get more at minefold.com'
          else
            allow_request(server)
          end
        end
      end
    end

    # TODO move into web. Or core.
    def access_policy(server)
      policies = {
        '1' => {
          whitelist: (server['settings']['whitelist'] || '').split
        },
        '2' => {
          blacklist: (server['settings']['blacklist'] || '').split
        }
      }

      access_policy = policies[0]
      if policy_id = server['access_policy_id']
        access_policy = policies[policy_id]
      end
    end

    def allow_request(server)
      @server_id = server['id'].to_i
      server_pc_id = server['server_pc_id']

      data = JSON.dump(
        name: server['name'],
        access: access_policy(server),
        settings: JSON.load(server['settings'])
      )

      funpack_pc_id = server['funpack_pc_id']

      start_server server_pc_id, funpack_pc_id, data
    end

    def verification_request(token)
      log(req: 'mojang_link')

      listen_once "players:verification_request:#{token}" do |response|
        info "verification response:#{response}"
        kick_player response
      end

      Resque.push 'high',
        class: 'LinkMojangAccountJob',
        args: [token, username]
    end

    def start_server(server_pc_id, funpack_pc_id, data)
      # if server_pc_id is nil, use a generated reply key until we have a real
      # server_pc_id
      reply_key = (server_pc_id || "req-#{BSON::ObjectId.new}")

      redis.sadd 'servers:shared', server_pc_id

      Scrolls.log({
        at: 'prism-back start_server',
        server_id: server_pc_id,
        data: data,
        funpack_id: funpack_pc_id,
        reply_key: reply_key
      })


      redis.lpush_hash "servers:requests:start",
        server_id: server_pc_id,
        data: data,
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
        kick_player reply['message'] || "Server failed to start. Please try again or contact support@minefold.com"
      end
    end

    def connect_player_to_server player_id, server_id, host, port
      info "connecting to #{host}:#{port}"

      # this tells prism to connect the player to the server
      # TODO new prism will always send reply_key
      if reply_key
        redis.publish_json reply_key,
          host: host,
          port: port,
          player_id: player_id,
          world_id: server_id
      else
        redis.publish_json "players:connection_request:#{username}",
          host: host,
          port: port,
          player_id: player_id,
          world_id: server_id
      end
    end
  end
end
