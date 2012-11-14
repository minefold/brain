module EventMachine
  class Multi
    include EventMachine::Deferrable

    attr_reader :requests, :responses

    def initialize
      @requests  = []
      @responses = {:callback => {}, :errback => {}}
    end

    def add name, deferrable
      @requests.push deferrable

      deferrable.callback { |result| @responses[:callback][name] = result; check_progress }
      deferrable.errback  { |result| @responses[:errback][name]  = result; check_progress }
    end

    def finished?
      (@responses[:callback].size + @responses[:errback].size) == @requests.size
    end

    protected

    # invoke callback if all requests have completed
    def check_progress
      succeed(@responses[:callback]) if finished?
    end
  end
end