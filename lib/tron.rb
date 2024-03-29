require 'date'

class Tron
  extend Resque::Helpers

  def self.server_started(timestamp, server_id, ip, port)
    Tron.enqueue 'LegacySessionStartedJob', server_id, timestamp.to_datetime.rfc3339, ip, port
  end

  def self.server_stopped(timestamp, server_id, exit_status)
    Tron.enqueue 'LegacySessionStoppedJob', server_id, timestamp.to_datetime.rfc3339, exit_status
  end

  def self.player_session_started(timestamp, server_id, distinct_id, username)
    Tron.enqueue 'LegacyPlayerSessionStartedJob', server_id, timestamp.to_datetime.rfc3339, distinct_id, username
  end

  def self.player_session_stopped(timestamp, server_id, distinct_id, username)
    Tron.enqueue 'LegacyPlayerSessionStoppedJob', server_id, timestamp.to_datetime.rfc3339, distinct_id, username
  end

  def self.enqueue(job, *args)
    if r = redis
      r.sadd "queues", "default"
      r.rpush "queue:default", encode(class: job, args: args)
    end
  end

  def self.publish(channel, msg='')
    if r = redis
      r.publish channel, msg
    end
  end

  def self.redis
    $tron_redis ||= Redis.connect(url: ENV['TRON_REDIS_URL'])
  end
end

