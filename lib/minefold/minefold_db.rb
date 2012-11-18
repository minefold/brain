class MinefoldDb
  def self.connection
    @connection ||= begin
      mongo = Mongo::Connection.from_uri(ENV['MONGO_URL'] || 'mongodb://localhost:27017')
      db_name = mongo.auths.any? ? mongo.auths.first['db_name'] : 'minefold'
      mongo[db_name]
    end
  end
end