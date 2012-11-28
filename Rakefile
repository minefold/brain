require 'bundler/setup'
Bundler.require :default

require 'resque/tasks'

$:.unshift File.join File.dirname(__FILE__), 'lib'

task "resque:setup" do
  require 'models'
  require 'jobs'
  require 'json'

  uri = URI.parse(ENV['REDIS_URL'] || 'redis://localhost:6379/')
  $redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
  Resque.redis = $redis
  
  $mongo = begin
    uri = ENV['MONGO_URL'] || 'mongodb://localhost:27017/minefold_development'
    mongo = ::Mongo::Connection.from_uri(uri)

    if mongo.is_a? ::Mongo::MongoReplicaSetClient
      # this should be in the damn ruby driver
      mongo_uri = ::Mongo::URIParser.new(uri)
      auth = mongo_uri.auths.first

      db = mongo[auth['db_name']]
      db.authenticate auth['username'], auth['password']
      db
    else
      db_name = mongo.auths.any? ? mongo.auths.first['db_name'] : nil
      db_name ||= URI.parse(uri).path[1..-1]
      mongo[db_name]
    end
  end
end