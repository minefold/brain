module Prism
  class QueuePopper
    include Logging

    def initialize queue, *a, &b
      @queue = queue
      @callback = EM::Callback(*a, &b)

      start_processing
    end

    def start_processing
      debug "processing #{@queue}"
      @redis = PrismRedis.connect
      listen
    end

    def listen
      @pop = @redis.brpop @queue, 30
      @pop.callback do |channel, item|
        if item
          @callback.call item
        end

        EM.add_timer(0.5) { listen }
      end
      @pop.errback { EM.add_timer(0.5) { listen } }
    end
  end

  class QueueProcessor
    include Logging

    def initialize klass
      @queue, @klass = klass.queue, klass
      @popper = QueuePopper.new klass.queue, method(:process)
    end

    def process item
      @klass.new.process item if item
    end
  end
end