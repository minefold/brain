module Prism
  class PlayerMinutePlayedEvent < Request
    include ChatMessaging
    include Logging

    process "players:minute_played", :world_id, :player_id, :username, :session_started_at, :session_id

    log_tags :session_id, :world_id, :player_id, :username

    MESSAGES = {
      15 => "15 minefold minutes left",
      5  =>  "5 minefold minutes left!"
    }

    ONBOARDING = ["signup at minefold.com for 10 hours free/month"]

    def run
      MinecraftPlayer.find_with_user(player_id) do |player|
        raise "unknown player:#{player_id}" unless player

        @mp_id, @mp_name, @remote_ip = player.distinct_id.to_s, player.username, player.last_remote_ip

        session_minutes = Time.parse(session_started_at).minutes_til(Time.now)
        info "played 1 minute [#{player.plan_status}] session:#{session_minutes} mins"

        player.update '$inc' => { 'minutes_played' => 1 }

        Session.update(
          { _id: BSON::ObjectId(session_id) },
          { '$inc' => { minutes_played: 1 } }
        )

        if player.limited_time?
          redis.hget_json "worlds:running", world_id do |world|
            if world
              @instance_id = world['instance_id']

              if player.user
                player.user.update '$inc' => { 'credits' => -1 }
              else
                send_onboarding_messages session_minutes, player
              end
            end
            credits_updated player
          end
        end
      end
    end

    def credits_updated player
      EM.add_timer(60) { redis.publish "players:disconnect:#{username}", "no credit" } if player.credits <= 1

      if (message = MESSAGES[player.credits]) || player.credits <= 1
        send_delayed_message 0, message if message

        if player.credits < 1
          EM.add_timer(1)  { send_world_player_message instance_id, world_id, username, "Top up your account at minefold.com" }
          EM.add_timer(40) { send_world_player_message instance_id, world_id, username, "Thanks for playing!" }
        end
      end

      # TODO credit reminder job
      # if player.credits == 30 and user = player.user
      #   EM.defer do
      #     Resque.push 'mailer', 'CreditReminder', user.id.to_s
      #   end
      # end
    end

    def send_onboarding_messages session_minutes, player
      if [1, 5, 15].include?(session_minutes) or (session_minutes % 30 == 0)
        send_delayed_message 0, ONBOARDING.first
      end
    end
  end
end