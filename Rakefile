require 'bundler/setup'
Bundler.require :default

require 'resque/tasks'
require 'rake/testtask'

$:.unshift File.join File.dirname(__FILE__), 'lib'

task :default => :test

task :test do
  Rake::TestTask.new do |t|
    require 'turn/autorun'

    t.libs.push "lib"
    t.test_files = FileList['test/*_test.rb']
    t.verbose = true
  end
end

def redis_connection
  uri = URI.parse(ENV['REDIS_URL'] || 'redis://localhost:6379/')
  Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

task "resque:setup" do
  Bundler.require(:worker)
  require 'models'
  require 'brain'
  require 'prism/back/funpack'
  require 'jobs'
  require 'json'

  $redis = redis_connection
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

namespace :funpack do
  task :start do
    redis_connection.lpush "servers:requests:start", JSON.dump(
      server_id: ENV['SERVER'],
      funpack_id: ENV['FUNPACK'],
      data: '',
    )
  end
end