class KickPlayerJob
  @queue = :pc

  def self.perform server_id, username, msg
    keys = $redis.keys("pinky:*:servers:#{server_id}")

    if keys.size == 0
      raise "server:#{server_id} not found"

    elsif keys.size > 1
      raise "multiple servers found:#{keys.join(',')}"

    else
      pinky_id = keys.first.split(':')[1]

      $redis.lpush "pinky:#{pinky_id}:in", JSON.dump(
        serverId: server_id,
        name: 'kick',
        username: username,
        msg: msg
      )
    end
  end
end