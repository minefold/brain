class StartServerJob
  @queue = :brain

  def self.perform server_id, funpack_id, world_id, settings
    $redis.lpush "worlds:requests:start", JSON.dump(
      server_id: server_id,
      world_id: world_id,
      settings: settings,
      funpack_id: funpack_id
    )
  end
end