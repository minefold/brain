require 'eventmachine/periodic_timer_with_timeout'
require 'eventmachine/cancellable_timeout'

# TODO this logic belongs in Minefold, not the Partycloud

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

    def run
      debug "processing #{username} #{target_host}"

      url = URI.parse(ENV['DATABASE_URL'])
      $pg = PG::Connection.new(
        host: url.host,
        port: url.port,
        user: url.user,
        password: url.password,
        dbname:url.path[1..-1]
      )

      host = target_host.split(':')[0]

      EM.defer(proc {
        servers = $pg.query(%Q{
            select servers.party_cloud_id,
                   servers.settings,
                   funpacks.party_cloud_id,
                   worlds.party_cloud_id

            from servers
              inner join funpacks on servers.funpack_id = funpacks.id
               left join worlds on worlds.server_id = servers.id

            where host=$1 and deleted_at is null
            limit 1
          }, [host])

        players = $pg.query(%Q{
            select players.id, users.credits from players
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
          server_id = servers.getvalue(0,0)
          settings = JSON.load(servers.getvalue(0,1))
          funpack_id = servers.getvalue(0,2)
          
          player_id = players.getvalue(0,0)
          credits = players.getvalue(0,1).to_i

          if credits <= 0
            kick_player 'No credits. Buy more at minefold.com'

          elsif !whitelisted?(username, settings)
            kick_player 'You are not white-listed on this server. Visit minefold.com'

          else
            player_allowed_to_connect player_id, server_id, funpack_id, settings
          end
        end
      })
    end

    def player_allowed_to_connect player_id, server_id, funpack_id, settings
      redis.get "server:#{server_id}:state" do |state|
        if state == 'up'
          redis.keys("pinky:*:servers:#{server_id}") do |keys|
            if key = keys.first
              pinky_id = key.split(':')[1]
              redis.get_json("box:#{pinky_id}") do |pinky|
                redis.get_json("pinky:#{pinky_id}:servers:#{server_id}") do |ps|
                  connect_player_to_server player_id, server_id, pinky['ip'], ps['port']
                end
              end
            else
              kick_player '500'
            end
          end
        else
          start_world player_id, server_id, funpack_id, settings
        end
      end
    end

    def start_world player_id, server_id, funpack_id, settings
      debug "server:#{server_id} is not running"
      redis.lpush_hash "worlds:requests:start",
        server_id: server_id,
        settings: settings,
        funpack_id: funpack_id

      redis.sadd "servers:shared", server_id
      listen_once_json "worlds:requests:start:#{server_id}" do |world|
        if world['host']
          connect_player_to_server player_id, server_id, world['host'], world['port']
        else
          kick_player world['failed']
        end
      end
    end

    def connect_player_to_server player_id, server_id, host, port
      info "connecting to #{host}:#{port}"

      # this tells prism they can connect the player to the server
      redis.publish_json "players:connection_request:#{username}",
        host: host,
        port: port,
        player_id: player_id,
        world_id: server_id
    end
  end
end
