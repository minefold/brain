require 'bundler/setup'
Bundler.require :default

def redis_connect
  uri = URI.parse(ENV['REDIS_URL'] || 'redis://localhost:6379/')
  Redis.new(
    host: uri.host,
    port: uri.port,
    password: uri.password
  )
end

$redis = redis_connect

def start_server server_id
  puts "starting #{server_id}"
  $redis.lpush "servers:requests:start", JSON.dump(
    server_id: server_id,
    settings: {},
    funpack_id: '50a976ec7aae5741bb000001',
    reply_key: server_id
  )
end

def stop_server server_id
  puts "stopping #{server_id}"
  $redis.lpush "servers:requests:stop", server_id
end

$servers = {}

def count_state(h, state)
  h.inject(0){|count, (_, s)| count + (s == state ? 1 : 0) }
end

Thread.abort_on_exception = true
Thread.new do
  redis_connect.psubscribe(
    "servers:requests:start:*", "servers:requests:stop:*") do |on|
    on.pmessage do |_, chan, msg|
      server = JSON.load(msg)
      server_id = chan.split(':')[3]

      $servers[server_id] = server['state']
      starting = count_state($servers, 'starting')
      started = count_state($servers, 'started')

      puts "starting: #{starting}  up: #{started}"
    end
  end
end

while true
  num_servers = count_state($servers, 'started')

  print "> "
  target_servers = gets.to_i

  if target_servers > num_servers
    (target_servers - num_servers).times do
      start_server BSON::ObjectId.new.to_s
    end

    started = 0
    while started < target_servers
      sleep 1
      started = count_state($servers, 'started')
    end

  else
    stop_count = num_servers - target_servers
    Hash[$servers.take(stop_count)].each do |server_id, _|
      stop_server server_id
    end

    started = num_servers
    while started > target_servers
      sleep 1
      started = count_state($servers, 'started')
    end
  end
end
