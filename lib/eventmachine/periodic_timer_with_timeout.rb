module EventMachine
  class PeriodicTimerWithTimeout
    attr_accessor :interval

    # Create a new periodic timer that executes every interval seconds
    def initialize interval, timeout
      @interval = interval
      @cancelled = false

      @timeout = EM.add_periodic_timer timeout, method(:timeout_fired)

      schedule
    end
    
    def callback &block
      return unless block
      @code = block
    end

    def timeout &block
      return unless block
      @timeout_code = block
    end
    
    def cancel
      @cancelled = true
      @timeout.cancel
    end

    def schedule
      EM.add_timer @interval, method(:fire)
    end

    def fire
      unless @cancelled
        @code.call self if @code
        schedule
      end
    end
    
    def timeout_fired
      unless @cancelled
        cancel
        @timeout_code.call if @timeout_code
      end
    end
  end
  
  def self.periodic_with_timeout interval, timeout
    PeriodicTimerWithTimeout.new interval, timeout
  end
end

