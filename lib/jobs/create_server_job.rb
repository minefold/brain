class CreateServerJob
  @queue = :pc

  def self.perform reply_key
    id = BSON::ObjectId.new
    Models::Server.insert(_id: id) do
      Resque.push 'high', class: 'ServerCreatedJob', args: [reply_key, id.to_s]
    end
  end
end