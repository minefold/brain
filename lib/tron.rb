class Tron
  extend Resque::Helpers
  
  def self.server_stopped(server_id, timestamp)
    Tron.enqueue 'LegacySessionStoppedJob', server_id, timestamp.to_i
    Tron.publish "servers:requests:stop:#{server_id}"
  end
  
  def self.enqueue job, *args
    if r = redis
      r.sadd "resque:queues", "high"
      r.rpush "resque:queue:high", encode(class: job, args: args)
    end
  end
  
  def self.publish(channel, msg='')
    if r = redis
      r.publish channel, msg
    end
  end
  
  def self.redis
    if url = ENV['TRON_REDIS_URL']
      Redis.connect(url: url)
    end
  end
end

