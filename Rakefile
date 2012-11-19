require 'bundler/setup'
Bundler.require :default

require 'resque/tasks'

$:.unshift File.join File.dirname(__FILE__), 'lib'

task "resque:setup" do
  require 'jobs'
  uri = URI.parse(ENV['REDIS_URL'] || 'redis://localhost:6379/')
  $redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
  Resque.redis = $redis
end