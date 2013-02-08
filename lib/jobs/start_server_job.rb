class StartServerJob
  @queue = :pc

  def self.perform server_id, funpack_id, data
    $redis.lpush "servers:requests:start", JSON.dump(
      server_id: server_id,
      funpack_id: funpack_id,
      settings: data,
      data: data
    )
  end
end