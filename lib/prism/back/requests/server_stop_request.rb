require 'tron'

module Prism
  class ServerStopRequest < Request
    include Logging
    include Messaging

    process "servers:requests:stop", :server_id

    attr_reader :server_id

    log_tags :server_id

    def reply options = {}
      redis.publish_json "servers:requests:stop:#{server_id}", options
    end

    def run
      redis.get "server:#{server_id}:state" do |state|
        case state
        when 'starting'
          debug "stop request ignored: server:#{server_id} is starting"
          stopped

        when 'stopping'
          debug "stop request ignored: server:#{server_id} is already stopping"
          stopped
          
        when 'up'
          debug "stopping server:#{server_id}"
          stop_server

        else
          debug "stop request ignored: server:#{server_id} is not running"
          stopped
          
        end
      end
    end

    def stop_server
      redis.keys("pinky:*:servers:#{server_id}") do |keys|
        if keys.size == 0
          reply failed: 'server not found'
        elsif keys.size > 1
          reply failed: 'multiple servers found'
        else
          pinky_id = keys.first.split(':')[1]

          redis.lpush_hash "pinky:#{pinky_id}:in",
            name: 'stop',
            serverId: server_id
        end
      end
    end
    
    def stopped
      Tron.server_stopped server_id, Time.now
    end
  end
end