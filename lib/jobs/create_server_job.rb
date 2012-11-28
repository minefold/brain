class CreateServerJob
  @queue = :pc

  def self.perform reply_key
    id = BSON::ObjectId.new
    puts "[CreateServerJob] assiged id:#{id}"
    Models::Server.insert(_id: id) do
      puts "[CreateServerJob] created server id:#{id} reply:#{reply_key}"
      Resque.push 'high', class: 'ServerCreatedJob', args: [reply_key, id.to_s]
    end
  end
end