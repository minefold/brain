# TODO this logic belongs in Minefold, not the Party Cloud

module Prism
  class PlayerConnectionRequest < Request
    include Messaging
    include Logging
    include Back::PlayerConnection
    include ChatMessaging

    process "players:connection_request", :username, :target_host, :remote_ip

    log_tags :username

    def kick_player message
      redis.publish "players:disconnect:#{username}", message
    end

    def whitelisted?(username, settings)
      whitelist = settings['whitelist'] || ''
      ops = settings['ops'] || ''

      (whitelist.split("\n") + ops.split("\n")).include?(username)
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

      EM.defer(proc {
        servers = pg.query(%Q{
            select servers.id,
                   servers.party_cloud_id,
                   servers.settings,
                   funpacks.party_cloud_id,
                   worlds.party_cloud_id

            from servers
              inner join funpacks on servers.funpack_id = funpacks.id
               left join worlds on worlds.server_id = servers.id

            where host=$1 and deleted_at is null
            limit 1
          }, [host])

        players = pg.query(%Q{
            select players.id, users.coins from players
              inner join users on users.id = players.user_id
            where players.game_id=$1
              and players.uid=$2
              and users.deleted_at is null
            limit 1
          }, [1, username])

        [servers, players]
      }, proc {|servers, players|

        if players.count == 0
          kick_player "Sign up to play here at minefold.com"

        elsif servers.count == 0
          kick_player "No server found, visit minefold.com"

        else
          # if this server hasn't run before, server_id will be nil
          @server_id = servers.getvalue(0,0)
          server_pc_id = servers.getvalue(0,1)
          settings = JSON.load(servers.getvalue(0,2))
          funpack_pc_id = servers.getvalue(0,3)

          @player_id = players.getvalue(0,0)
          coins = players.getvalue(0,1).to_i

          if coins <= 0
            kick_player 'No coins. Buy more at minefold.com'

          elsif !whitelisted?(username, settings)
            kick_player 'You are not white-listed on this server. Visit minefold.com'

          else
            start_world server_pc_id, funpack_pc_id, settings
          end
        end
      })
    end

    def start_world server_pc_id, funpack_pc_id, settings
      # if server_pc_id is nil, use a generated reply key until we have a real
      # server_pc_id
      reply_key = (server_pc_id || "req-#{BSON::ObjectId.new}")

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
