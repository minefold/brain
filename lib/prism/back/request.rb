module Prism
  class Request
    include Mongo

    class << self
      attr_reader :queue, :message_parts

      def process queue = nil, *message_parts

        @queue, @message_parts = queue, message_parts

        message_parts.each {|part| self.__send__(:attr_reader, "#{part}") }
      end
    end

    def redis; Prism.redis; end

    def process message
      parts = self.class.message_parts.size == 1 ? { self.class.message_parts.first => message } : JSON.parse(message)
      
      parts.each do |k,v| 
        if k =~ /^[0-9]/
          puts "INVALID INSTANCE VAR #{k}"
        else
          self.instance_variable_set(:"@#{k}", v)
        end
      end

      run
    end
  end
end