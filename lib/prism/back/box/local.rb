module Prism
  module Box
    class Local < Base
      def self.local_box
        @local_box ||= begin
          local_instance_id = `hostname`.strip
          puts "starting local box"
          Local.new local_instance_id
        end
      end

      def self.create options = {}
        op = EM::DefaultDeferrable.new
        EM.next_tick { op.succeed local_box }
        op
      end

      def self.all *c, &b
        cb = EM::Callback(*c, &b)
        cb.call Array(local_box)
        cb
      end

      def initialize instance_id
        @instance_id, @instance_type, @host = instance_id, 'm2.4xlarge', '0.0.0.0'
        @state = 'running'
        @started_at = Time.now
        @tags = {}
      end

      def query_state *c,&b
        cb = EM::Callback(*c,&b)
        cb.call 'running'
        cb
      end

    end
  end
end