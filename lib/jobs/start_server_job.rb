class StartServerJob
  @queue = :brain

  def self.perform server_id, funpack_id, settings
    $redis.lpush "servers:requests:start", JSON.dump(
      server_id: server_id,
      settings: settings,
      funpack_id: funpack_id
    )
  end
end