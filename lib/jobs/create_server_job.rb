class CreateServerJob
  @queue = :pc

  def self.perform reply_key
    id = BSON::ObjectId.new
    puts "[CreateServerJob] assiged id:#{id}"
    
    ts = Time.now

    $mongo['servers'].insert(
      _id: id,
      created_at: ts,
      updated_at: ts
    )

    puts "[CreateServerJob] created server id:#{id} reply:#{reply_key}"
    Resque.push 'high', class: 'ServerCreatedJob', args: [reply_key, id.to_s]
  end
end