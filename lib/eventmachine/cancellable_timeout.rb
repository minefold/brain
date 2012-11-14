module EventMachine
  class CancellableTimeout
    attr_accessor :interval

    # Create a timeout that can be cancelled
    def initialize timeout, &block
      @cancelled = false
      @callback = block

      EM.add_timer timeout, method(:fire)
    end

    def cancel
      @cancelled = true
    end

    def fire
      unless @cancelled
        @callback.call if @callback
      end
    end
  end

  def self.set_timeout timeout, &block
    CancellableTimeout.new timeout, &block
  end
end

