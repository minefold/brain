module EM
  def self.stop_gracefully
    @gracefully_stopping = false
    Signal.trap('QUIT') do
      if running_workers.empty?
        EM.stop
      else
        puts "Stopping (#{running_workers.size} tasks)"
        @gracefully_stopping = true
      end
    end
  end

  def self.running_workers
    @running_workers ||= []
  end

  def self.start_work klass, *args
    worker = klass.new
    @running_workers = running_workers | [worker]
    worker.run *args
  end

  def self.finish_work worker
    @running_workers = running_workers - [worker]
    EM.stop if @gracefully_stopping && running_workers.empty?
  end
end
