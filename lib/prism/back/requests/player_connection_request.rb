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

      redis.publish_json reply_key, failed: message
    end

    def db
      $db ||= begin
        db = Sequel.connect(ENV['DATABASE_URL'] || 'postgres://localhost/minefold_development')
        db.extension :pg_array
        db
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
        id = $1.to_i
        # validate integer range before PG query
        if id < 0 || id > 2147483647
          nil
        else
          ['servers.id=?', $1]
        end
      else
        log(lookup: 'cname', host: host)
        ['servers.cname=?', host]
      end

      if query
        EM.defer(proc {
          statement = %Q{
              select servers.id,
                     servers.name,
                     servers.party_cloud_id as server_pc_id,
                     servers.settings,
                     servers.shared,
                     servers.access_policy_id,
                     funpacks.party_cloud_id as funpack_pc_id,
                     funpacks.bolt_allocations,
                     worlds.party_cloud_id as snapshot_pc_id,
                     users.coins as creator_coins,
                     users.username as creator_username,
                     subscriptions.expires_at as subscription_expires_at,
                     plans.bolts as plan_bolts

              from servers
                inner join funpacks on servers.funpack_id = funpacks.id
                 left join worlds on worlds.server_id = servers.id
                inner join users on servers.creator_id = users.id
                 left join subscriptions on users.subscription_id = subscriptions.id
                 left join plans on subscriptions.plan_id = plans.id

              where #{query[0]} and servers.deleted_at is null
              limit 1
            }
          db[statement, query[1]].first
        }, cb)
      else
        cb.call nil
      end
      cb
    end

    def find_player_by_username(username, *a, &b)
      cb = EM::Callback(*a, &b)
      EM.defer(proc {
        db[%Q{
            select accounts.id, users.coins from accounts
              inner join users on users.id = accounts.user_id
            where accounts.type = ?
              and accounts.uid = ?
              and users.deleted_at is null
            limit 1
          }, 'Accounts::Mojang', username].first
      }, cb)
    end

    def connection_request(host)
      find_server_by_host(host) do |server|
        if server.nil?
          kick_player "Server not found. Check the address on minefold.com"
        else
          valid_client(server)
        end
      end
    end

    def valid_client(server)
      funpack = Funpack.find(server[:funpack_pc_id])
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
      if server[:shared]
        shared_server(server)
      else
        normal_server(server)
      end
    end

    def normal_server(server)
      if has_credit?(server)
        allow_request(server)
      else
        kick_player "#{server[:creator_username]} is out of credit. Bug them!"
      end
    end

    def has_credit?(server)
      subscription_expiry = server[:subscription_expires_at] || (Time.now - 1)

      (subscription_expiry > Time.now) || server[:creator_coins] > 0
    end

    def shared_server(server)
      find_player_by_username(username) do |player|
        if player.nil?
          kick_player "Link your Minecraft account at minefold.com"
        else
          if player[:coins] <= 0
            kick_player 'Out of time! Get more at minefold.com'
          else
            allow_request(server)
          end
        end
      end
    end

    # TODO move into web. Or core.
    def access_policy(server)
      settings = JSON.parse(server[:settings] || '{}')

      policies = {
        '1' => {
          whitelist: (settings['whitelist'] || '').split
        },
        '2' => {
          blacklist: (settings['blacklist'] || '').split
        }
      }

      policy = policies[0]
      if policy_id = server[:access_policy_id]
        policy = policies[policy_id.to_s]
      end
      policy
    end

    def allow_request(server)
      @server_id = server[:id]
      server_pc_id = server[:server_pc_id]
      funpack_pc_id = server[:funpack_pc_id]

      if plan_bolts = server[:plan_bolts]
        # allocate based on subscription plan
        allocation = "#{server[:bolt_allocations][plan_bolts - 1]}Mb"
        Scrolls.log({
          at: 'using_subscription',
          expires_at: server[:subscription_expires_at],
          bolts: plan_bolts,
          allocation: allocation
        })
        
      else
        # leave allocation up to brain
        allocation = nil
      end

      start_server(server_pc_id, funpack_pc_id, allocation, JSON.dump(
        name: server[:name],
        access: access_policy(server),
        settings: JSON.load(server[:settings] || '{}')
      ))
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

    def start_server(server_pc_id, funpack_pc_id, allocation, data)
      redis.sadd 'servers:shared', server_pc_id

      redis.lpush_hash "servers:requests:start",
        server_id: server_pc_id,
        data: data,
        funpack_id: funpack_pc_id,
        reply_key: server_pc_id,
        allocation: allocation

      listen_once_json "servers:requests:start:#{server_pc_id}", method(:reply_handler)
    end

    def reply_handler reply
      if reply['server_id']
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

      redis.publish_json reply_key,
        host: host,
        port: port,
        player_id: player_id,
        world_id: server_id
    end
  end
end
