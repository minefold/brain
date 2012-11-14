module Prism
  class BusyOperationRequest < Request
    def run
      op = redis.set_busy *busy_hash
      op.callback do
        deferred_operation do
          redis.hdel *busy_hash[0..1]
        end
      end
    end

    def deferred_operation &blk
      start_time = Time.now

      deferrable = perform_operation
      deferrable.callback do |result|
        operation_succeeded result
        yield
      end

      deferrable.errback do |error|
        error "operation failed", error
        operation_failed
        yield
      end
    end
  end
end