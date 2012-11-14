module EM
  class RPCConnection < Connection
    def initialize data, timeout, one_packet, callback
      @data, @timeout, @one_packet, @callback = data, timeout, one_packet, callback
      
      @responded = false
      @timed_out = false
      @received = nil
    end

    def post_init
      EM.add_timer(@timeout) do
        @timed_out = true
        close_connection
      end
      
      send_data @data
    end

    def receive_data data
      (@received ||= "") << data
      close_connection if @one_packet
    end
    
    def unbind
      if @callback
        @callback.call @timed_out ? nil : @received
      end
    end
  end

  # expects the server to hang up when it's finished sending data
  def self.rpc host, port, data, timeout, *a, &b
    cb = EM::Callback *a, &b if a.any? || b
    EM.connect host, port, RPCConnection, data, timeout, false, cb
    cb
  end
  
  # hangs up when any data is received
  def self.rpc_packet host, port, data, timeout, *a, &b
    cb = EM::Callback *a, &b if a.any? || b
    EM.connect host, port, RPCConnection, data, timeout, true, cb
    cb
  end

  # retries several times on no data returned
  def self.rpc_retry host, port, data, timeout, retries, *a, &b
    cb = EM::Callback *a, &b if a.any? || b
    
    puts "#{host}:#{port} -> #{data} retries: #{retries}"
    
    if retries > 0
      handler = proc {|result| 
          if result
            cb.call result
          else
            rpc_retry host, port, data, timeout, retries - 1, cb
          end
        }
      
      EM.connect host, port, RPCConnection, data, timeout, false, handler
    else
      cb.call nil
    end
    cb
  end
end