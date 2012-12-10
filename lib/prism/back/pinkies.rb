module Prism
  class Pinkies < Array
    def self.redis
      Prism.redis
    end

    def self.collect *a, &b
      cb = EM::Callback(*a, &b)

      inject_heartbeats({}) do |h|
        inject_pinky_states(h) do |h|
          inject_pinky_servers(h) do |h|
            inject_box_info(h) do |h|
              cb.call Pinkies.from_hash(h)
            end
          end
        end
      end

      cb
    end

    def self.inject_heartbeats(initial, *a, &b)
      cb = EM::Callback(*a, &b)
      redis.keys("pinky:*:heartbeat") do |keys|
        EM::Iterator.new(keys, 10).inject(initial, proc{ |h,key,iter|
          redis.get(key) do |hb|

            id = key.split(':')[1]

            h[id] ||= {}
            begin
              heartbeat = JSON.load(hb)
              h[id].merge!(heartbeat)
            rescue => e
              # if pinky is acting up this might not be valid json
              puts e
            end

            iter.return(h)
          end
         }, proc{ |h| cb.call h })
      end
      cb
    end

    def self.inject_pinky_states(initial, *a, &b)
      cb = EM::Callback(*a, &b)
      redis.keys("pinky:*:state") do |keys|
        EM::Iterator.new(keys, 10).inject(initial, proc{ |h,key,iter|
          redis.get(key) do |state|
            id = key.split(':')[1]

            h[id] ||= {}
            h[id].merge!('state' => state)

            iter.return(h)
          end
         }, proc{ |h| cb.call h })
      end
      cb
    end

    def self.inject_pinky_servers(initial, *a, &b)
      cb = EM::Callback(*a, &b)
      redis.keys("pinky:*:servers:*") do |keys|
        EM::Iterator.new(keys, 10).inject(initial, proc{ |h,key,iter|
          redis.get(key) do |state|
            _, pinky_id, _, server_id = key.split(':')

            h[pinky_id] ||= {}
            h[pinky_id]['servers'] ||= []
            h[pinky_id]['servers'] << server_id

            iter.return(h)
          end
         }, proc{ |h| cb.call h })
      end
      cb
    end

    def self.inject_box_info(initial, *a, &b)
      cb = EM::Callback(*a, &b)
      redis.keys("box:*") do |keys|
        EM::Iterator.new(keys, 10).inject(initial, proc{ |h,key,iter|
          redis.get(key) do |info|
            id = key.split(':')[1]

            h[id] ||= {}
            h[id].merge!(JSON.load(info))

            iter.return(h)
          end
         }, proc{ |h| cb.call h })
      end
      cb
    end

    def self.from_hash h
      pinkies = Pinkies.new
      h.each do |id, h|
        pinkies << Pinky.new(
          id,
          Time.at(h['started_at'] || 0),
          h['state'],
          h['freeDiskMb'],
          h['freeRamMb'],
          h['idleCpu'],
          BoxType.find(h['type']),
          (h['servers'] ||[]).map{|server_id| Server.new(server_id) }
        )
      end
      pinkies
    end
  end
end