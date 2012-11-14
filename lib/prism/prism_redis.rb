# encoding: UTF-8

module Prism
  class << self
    attr_writer :redis
    def redis
      @redis ||= PrismRedis.connect
    end

    attr_writer :redis_factory
    def hiredis_connect
      @redis_factory ? @redis_factory.call : EM::Hiredis.connect(ENV['REDISTOGO_URL'] || REDISTOGO_URL)
    end

    attr_accessor :prism_id
  end

  class PrismRedis
    include Logging

    attr_reader :redis

    def self.connect
      new Prism.hiredis_connect
    end

    def self.psubscribe channel, *a, &b
      cb = EM::Callback *a, &b
      subscription = Prism::PrismRedis.connect
      subscription.psubscribe channel
      subscription.on :pmessage do |key, channel, message|
        cb.call key, channel, message
      end
      subscription
    end

    def initialize connection
      @redis = connection
      @redis.errback {|e| error "failed to connect to redis: #{e}" }
      @redis
    end

    def prism_id
      self.class.prism_id
    end

    def store_running_box box
      zadd "boxes:stopped", "inf", box.instance_id
      hset_hash "workers:running", box.instance_id, box.to_hash
    end

    def unstore_running_box instance_id, host
      zadd "boxes:stopped", Time.now.to_i, instance_id
      hdel "workers:running", instance_id
      publish "workers:requests:stop:#{instance_id}", host
    end

    def store_running_world world_id, instance_id, host, port, slots
      world_hash = {
        instance_id: instance_id,
        host: host,
        port: port,
        slots: slots
      }

      hset_hash "worlds:running", world_id, world_hash
      hdel "worlds:busy", world_id
      publish_json "worlds:requests:start:#{world_id}", world_hash
    end

    def unstore_running_world instance_id, world_id
      hdel "worlds:running", world_id
    end

    def get_json key, *a, &b
      cb = EM::Callback *a, &b
      op = get key
      op.callback {|data| cb.call data ? JSON.parse(data) : nil }
      cb
    end

    def hget_json key, field
      op = hget key, field
      op.callback {|data| yield data ? JSON.parse(data) : nil }
      op
    end

    def hgetall_json key
      df = EM::DefaultDeferrable.new

      op = redis.hgetall key
      op.callback {|data| df.succeed data.each_slice(2).each_with_object({}) {|w, hash| hash[w[0]] = JSON.parse w[1] } }
      op.errback  { df.errback }
      df
    end

    def hgetall key
      df = EM::DefaultDeferrable.new

      op = redis.hgetall key
      op.callback {|data| df.succeed data.each_slice(2).each_with_object({}) {|w, hash| hash[w[0]] = w[1] } }
      op.errback  { df.errback }
      df
    end

    def hset_hash channel, key, value
      hset channel, key, value.to_json
    end

    def set_busy key, field, state, options = {}
      hset_hash key, field, { state: state }.merge(options).merge({at: Time.now.to_i})
    end

    def lpush_hash list, value
      lpush list, value.to_json
    end

    def publish_json channel, hash
      publish channel, hash.to_json
    end

    def method_missing sym, *args, &blk
      redis.send sym, *args, &blk
    end

    %w[brpop hexists hget hset lpush publish scard sadd srem smembers sunion zadd zcard zcount].each do |cmd|
      define_method(:"#{cmd}") do |*args, &blk|
        op = redis.send cmd, *args
        op.errback {|e| handle_error e }
        op
      end
    end

    def handle_error e
      error "REDIS: #{e}"
    end


  end
end