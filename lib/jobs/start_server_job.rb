class StartServerJob
  @queue = :pc

  def self.perform server_id, funpack_id, data
    $redis.lpush "servers:requests:start", JSON.dump(
      server_id: server_id,
      funpack_id: funpack_id,
      data: data # TODO: shouldn't be sent as JSON from web
    )
  end
end