require 'minecraft/packet'
require 'eventmachine/rpc'

module Prism
  module WorldCollector
    def initialize timeout, df
      @timeout = timeout
      @df = df
    end

    def post_init
      send_data "worlds"
    end

    def receive_data data
      @data ||= ""
      @data << data
    end

    def unbind
      @timeout.cancel
      if @data
        json_data = JSON.parse(@data) rescue nil
        @df.succeed json_data
      else
        @df.fail
      end
    end
  end

  module Box
    def self.box_class
      case Fold.workers
      when :local
        Local
      when :cloud
        Cloud
      end
    end

    def self.all *c, &b
      box_class.all *c, &b
    end

    def self.find *c, &b
      box_class.find *c, &b
    end

    def self.create options = {}
      box_class.create options
    end

    class Base
      attr_reader :instance_id, :instance_type, :host, :started_at, :tags

      def uptime
        ((Time.now - started_at) / 60).to_i
      end

      def query_worlds timeout = 20
        df = EM::DefaultDeferrable.new
        
        @timeout = EM.add_periodic_timer(timeout) do
          puts "timeout querying worlds instance_id:#{instance_id} host:#{host}"
          df.fail "timeout"
        end
        
        EM.rpc host, 3000, "worlds", 10 do |result|
          @timeout.cancel
          if result and result.length > 0
            df.succeed JSON.load(result)
          else
            df.fail
          end
        end

        df
      end      
      
      def query_prism packet, timeout, *a, &b
        cb = EM::Callback *a, &b
        EM.rpc TEST_PRISM, 25565, packet, timeout do |result|
          cb.call result
        end
        cb
      end
      
      def ping_world world_port, *a, &b
        cb = EM::Callback *a, &b

        brain_ping = Minecraft::Packet.new 0xE1,
          :host => :string,
          :port => :int

        packet = brain_ping.create(host: host, port: world_port)
        
        query_prism packet, 2, cb
        
        cb
      end

      def to_hash
        {
            instance_id:instance_id,
                   host:host,
             started_at:started_at,
          instance_type:instance_type,
                   tags:tags
        }
      end
    end

  end
end