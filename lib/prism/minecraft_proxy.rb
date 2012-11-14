module Prism
  module MinecraftProxy
    attr_accessor :client

    def initialize client, buffered_data
      @client, @buffered_data = client, buffered_data
    end

    def post_init
      send_data @buffered_data
    end

    def receive_data data
      @client.send_data data
    end

    def unbind
      @client.server_unbound
    end
  end
end