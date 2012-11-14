require 'eventmachine/periodic_timer_with_timeout'
require 'eventmachine/cancellable_timeout'

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

    def run
      debug "processing #{username} #{target_host}"

      MinecraftPlayer.upsert_by_username_with_user(username, remote_ip) do |player, new_record|
        debug "player:#{player.id} user:#{player.user.id if player.user}"
        @mp_id, @mp_name, @remote_ip = player.distinct_id.to_s, player.username, player.last_remote_ip

        # TODO: support other hosts besides minefold.com
        if target_host =~ /^(\w+)\.(\w{1,16})\.minefold\.com\:?(\d+)?$/
          if $2 == 'verify'
            verify_player player, $1
          else
            World.find_by_name($2, $1) do |world|
              connect_unvalidated_player_to_unknown_world(player, world)
            end
          end
        else
          # connecting to a different host, probably pluto, old sk00l
          connect_to_current_world player
        end
      end
    end

    def verify_player player, token
      if player.verified?
        Resque.push 'high', class: 'UserAlreadyVerifiedJob', args: [username, token]
        kick_player "#{username} is linked to a different minefold.com account!"

      else
        debug "verifying player with code:#{token}"
        User.find_by_verification_token(token) do |user|
          if user
            puts "authenticating #{user.inspect}"
            authenticate_player do |result|
              puts "authentication result #{result}"

              case result
              when :success
                Resque.push 'high', class: 'UserVerifiedJob', args: [username, token]
                kick_player "Done! Your account is now verified"

              when :invalid_player
                kick_player "Bad account! #{username} is not a real minecraft.net account"

              end
            end
          else
            debug "invalid token"
            kick_player "Bad code! Check your verification address on minefold.com"
          end
        end
      end
    end

    def authenticate_player *a, &b
      cb = EM::Callback *a, &b

      if username.strip.downcase != 'player'
        cb.call :success
      else
        cb.call :invalid_player
      end


      # connection_hash = rand(36 ** 10).to_s(16)
      #       redis.publish "players:authenticate:#{username}", connection_hash
      #       timer = EM.periodic_with_timeout(0.5, 15)
      #       timer.timeout do
      #         cb.call :invalid_player
      #       end
      #       timer.callback do |timer|
      #         url = "http://session.minecraft.net/game/checkserver.jsp?user=#{username}&serverId=#{connection_hash}"
      #         p url
      #         http = EventMachine::HttpRequest.new(url).get
      #         http.callback do
      #           if http.response.strip == 'YES'
      #             p http.response
      #             timer.cancel
      #             cb.call :success
      #           end
      #         end
      #       end
      cb
    end

    def connect_unvalidated_player_to_unknown_world player, world
      if world
        world.has_data_file? do |has_data_file|
          if has_data_file
            debug "world:#{world.id} found"
            connect_unvalidated_player_to_world player, world
          else
            error "world:#{world.id} data_file:#{world.world_data_file} does not exist"
            reject_player username, '500',
              details: "world data #{world.world_data_file} not found"
          end
        end
      else
        debug "world not found"
        reject_player username, :unknown_world
      end
    end

    def current_players world_id, *a, &b
      cb = EM::Callback(*a, &b)
      op = redis.hgetall "players:playing"
      op.callback do |players|
        player_ids = players.select {|player_id, player_world_id| player_world_id == world_id.to_s }.keys.map{|id| BSON::ObjectId(id) }
        debug "players online:#{player_ids.join(',')}"

        cb.call player_ids
      end
      cb
    end

    def current_ops world, *a, &b
      cb = EM::Callback *a, &b
      current_players(world.id) do |player_ids|
        op_ids = world.opped_player_ids & player_ids
        debug "ops online:#{op_ids.join(',')}"
        cb.call op_ids
      end
      cb
    end

    def request_whitelist_connect player, world, *a, &b
      cb = EM::Callback *a, &b
      current_ops(world) do |op_ids|
        if op_ids.empty?
          # no ops online? no whitelist
          cb.call false
        else
          MinecraftPlayer.find_all({deleted_at: nil, _id: { '$in' => op_ids}}) do |ops|
            debug "ops online:#{ops.map(&:username).join(',')}"
            request_whitelist(world, player, ops) do |accepted|
              cb.call accepted
            end
          end
        end
      end
      cb
    end

    def request_whitelist world, player, ops, *a, &b
      cb = EM::Callback *a, &b
      redis.hget_json "worlds:running", world.id.to_s do |running_world|
        if world and running_world
          instance_id = running_world['instance_id']
          ops.each do |op|
            send_world_player_message instance_id, world.id, op.username, "#{username} wants to join!"
            send_world_player_message instance_id, world.id, op.username, "/whitelist add #{username} to accept"
          end
          listen_once("worlds:#{world.id}:whitelist_change:#{player.id}") do |action|
            cb.call action == 'added'
          end
        else
          warn "world not running?"
          cb.call false
        end
      end
      cb
    end

    def connect_unvalidated_player_to_world player, world
      if not player.has_credit?
        no_credit_player_connecting

      elsif world.banned?(player)
        debug "world:#{world.id} player:#{player.id} is banned"
        reject_player username, :banned

      elsif not (world.whitelisted?(player) or world.op?(player))
        debug "world:#{world.id} player:#{player.id} is not whitelisted"

        whitelist_timeout = EM.set_timeout(20) do
          reject_player username, :not_whitelisted
          cancel_listener "worlds:requests:whitelist_change:#{player.id}"
        end

        request_whitelist_connect player, world do |accepted|
          whitelist_timeout.cancel

          if accepted
            debug "world:#{world.id} player:#{player.id} whitelist request accepted"
            connect_player_to_world player, world
          else
            reject_player username, :not_whitelisted
          end
        end

      else
        debug "world:#{world.id} player:#{player.id} allowed to join"
        connect_player_to_world player, world
      end
    end

    def connect_player_to_world player, world
      player_id, world_id = player.id.to_s, world.id.to_s

      redis.lpush_hash "players:world_request",
       username: username,
       player_id: player_id,
        world_id: world_id,
        description: world.name
    end

    def unrecognised_player_connecting
      info "unrecognised"
      reject_player username, :unrecognised_player
    end

    def no_credit_player_connecting
      info "user:#{username} has no credit"
      reject_player username, :no_credit
    end

    # TODO: remove this method when we don't have "current worlds"
    def connect_to_current_world player
      if player.user
        debug "found user:#{player.user.id} host:#{target_host}"
        if player.user.current_world_id
          World.find(player.user.current_world_id) {|world| connect_to_world player, world }
        else
          info "user has no current_world"
          reject_player username, :no_world
        end
      else
        unrecognised_player_connecting
      end
    end

    # TODO: remove this old school path
    def connect_to_world player, world
      if world
        world.has_data_file? do |has_data_file|
          if has_data_file
            debug "world:#{world.id} found"
            connect_unvalidated_player_to_current_world player, world
          else
            error "world:#{world.id} data_file:#{world.world_data_file} does not exist"
            reject_player username, '500',
              details:"world data #{world.world_data_file} not found"
          end
        end
      else
        debug "old sk00l world not found"
        reject_player username, :no_world
      end
    end

    def connect_unvalidated_player_to_current_world player, world
      if not player.has_credit?
        no_credit_player_connecting
      else
        connect_player_to_world player, world
      end
    end
  end
end
