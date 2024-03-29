require 'uri'
require 'redis'
require 'bson'
require 'json'
require 'mongo'

$:.unshift File.join File.dirname(__FILE__), '../lib'
require 'prism/prism_mongo'

def redis_connect
  uri = URI.parse(ENV['REDIS_URL'] || 'redis://localhost:6379/')
  Redis.new(
    host: uri.host,
    port: uri.port,
    password: uri.password
  )
end

$redis = redis_connect

include Prism::Mongo

$mongo = mongo_connect
$server_ids = $mongo['servers'].find({}).limit(100).map{|s| s['_id']}

def start_server server_id
  puts "starting #{server_id}"
  $redis.lpush "servers:requests:start", JSON.dump(
    server_id: server_id,
    data: JSON.dump(settings: {
      ops: 'whatupdave'
    }),
    funpack_id: '50bec3967aae5797c0000004',
    reply_key: server_id
  )
end

def stop_server server_id
  puts "stopping #{server_id}"
  $redis.lpush "servers:requests:stop", server_id
end

$servers = {}
keys = $redis.keys 'server:*:state'
keys.each do |key|
  server_id = key.split(':')[1]
  $servers[server_id] = $redis.get(key)
end

def in_state(state)
  $servers.select{|_, s| s == state}
end

def count_state(state)
  in_state(state).size
end

Thread.abort_on_exception = true
Thread.new do
  redis_connect.psubscribe(
    "servers:requests:start:*", "servers:requests:stop:*") do |on|
    on.pmessage do |_, chan, msg|
      server = JSON.load(msg)
      server_id = chan.split(':')[3]

      $servers[server_id] =
        (server['state'] == 'started' ? 'up' : server['state'])

      puts "starting: #{count_state('starting')}  up: #{count_state('up')}"
    end
  end
end

$num_servers = count_state('up')
puts "starting: #{count_state('starting')}  up: #{count_state('up')}"

def change_servers target_servers
  if target_servers > $num_servers
    (target_servers - $num_servers).times do
      new_server_id = $server_ids.shift
      start_server new_server_id.to_s
      sleep 1
    end

    up = 0
    while up < target_servers
      sleep 1
      up = count_state('up')
    end

  else
    stop_count = $num_servers - target_servers
    Hash[in_state('up').take(stop_count)].each do |server_id, _|
      stop_server server_id
      sleep 1
    end

    up = $num_servers
    while up > target_servers
      sleep 1
      up = count_state('up')
    end
  end
end

def change_players server_id, count
  $redis.del "server:#{server_id}:players"
  $redis.sadd "server:#{server_id}:players", count.times.to_a
end

def reallocate_server server_id, slots
  $redis.lpush 'servers:reallocate_request', JSON.dump(
    server_id: server_id,
    slots: slots
  )
end

while true
  num_servers = count_state('up')

  print "> "
  command = gets.strip

  if command =~ /s (\d+)/
    change_servers $1.to_i

  elsif command =~ /p ([\d\w]+) (\d+)/
    change_players $1, $2.to_i

  elsif command =~ /r ([\d\w]+) (\d+)/
    reallocate_server $1, $2.to_i
  end
end
