module Prism
  class Pinkies < Array
    def self.redis
      $redis_sync = begin
        uri = URI.parse(ENV['REDIS_URL'] || 'redis://localhost:6379/')
        Redis.new(host: uri.host, port: uri.port, password: uri.password)
      end
    end

    def self.collect(*a, &b)
      cb = EM::Callback(*a, &b)
      EM.defer(method(:collect_sync), cb)
      cb
    end
    
    def self.collect_sync
      servers = collect_servers_sync
      
      pinkies = Pinkies.new
      collect_pinkies_sync.each do |pinky_id, h|
        pinkies << Pinky.new(
          pinky_id,
          Time.at(h['started_at'] || 0),
          h[:state],
          h['freeDiskMb'],
          h['freeRamMb'],
          h['idleCpu'],
          BoxType.find(h['type']),
          (servers[pinky_id] ||[]).map{|s| Server.new(s[:server_id], s[:ram_alloc], s[:slots]) }
        ) # TODO deprecate slots
      end
      pinkies
    end
    
    def self.collect_servers_sync
      redis.keys("pinky:*:servers:*").inject({}) do |h, key|
        _, pinky_id, _, server_id = key.split(':')
        h[pinky_id] ||= []
        h[pinky_id] << {
          server_id: server_id,
          slots: redis.get("server:#{server_id}:slots").to_i,
          ram_alloc: redis.get("server:#{server_id}:ram_alloc").to_i
        }
        h
      end
    end
    
    def self.collect_pinkies_sync
      redis.keys("pinky:*:heartbeat").inject({}) do |h, heartbeat_key|
        id = heartbeat_key.split(':')[1]
        
        heartbeat = JSON.load(redis.get(heartbeat_key)) rescue nil
        box = JSON.load(redis.get("box:#{id}")) rescue nil
        if heartbeat && box
          h[id] = {
            state: redis.get("pinky:#{id}:state"),
          }.merge(heartbeat).merge(box)
        end
        h
      end
    end
  end
end