class StartServerJob
  @queue = :pc

  def self.perform server_id, funpack_id, settings
    $redis.lpush "servers:requests:start", JSON.dump(
      server_id: server_id,
      funpack_id: funpack_id,
      settings: settings,
    )
  end
end