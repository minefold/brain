class StopServerJob
  @queue = :pc

  def self.perform server_id
    $redis.lpush "servers:requests:stop", server_id
  end
end