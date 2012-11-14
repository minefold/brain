module Prism
  module ChatMessaging
    attr_reader :instance_id # make sure you set this

    def pluralize amount, singular
      "#{amount} #{singular}#{amount == 1 ? '' : 's'}"
    end

    def time_in_words minutes
      case
      when minutes < 60
        pluralize(minutes, "minute")
      else
        pluralize(minutes / 60, "hour")
      end
    end

    def send_delayed_message delay, *lines
      EM.add_timer(delay) {
        lines.each do |line|
          send_world_player_message instance_id, world_id, username, line
        end
      }
    end

    def send_world_player_message instance_id, world_id, username, line
      world_stdin = "workers:#{instance_id}:worlds:#{world_id}:stdin"
      redis.publish world_stdin, "tell #{username} #{line}"
    end

    def send_world_message instance_id, world_id, message
      world_stdin = "workers:#{instance_id}:worlds:#{world_id}:stdin"
      redis.publish world_stdin, "say #{message}"
    end
  end
end