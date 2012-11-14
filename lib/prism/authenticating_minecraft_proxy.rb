module Prism
  module AuthenticatingMinecraftProxy
    include EM::P::Minecraft::Client

    attr_accessor :client
    attr_reader :username

    def initialize client, username
      @client, @username = client, username
      @buffer = ""
      @authenticated = false
    end

    def post_init
      send_packet 0x02, username: username
    end

    def receive_packet header, packet
      case header
      when 0x02
        EM.add_timer(0.5) { send_packet 0x01, protocol_version:17, username:username, map_seed:0, dimension:0, unused1:0, unused2:0,  unused3:0, unused4:0, unused5:0, unused6:0 }
      when 0x01
        @authenticated = true
      end
    end

    def receive_data data
      if @authenticated
        send_client_data data
      else
        authenticating_receive_data data
      end
    end

    def authenticating_receive_data data
      remainder = @buffer + data
      @buffer = ""

      begin
        p " < #{remainder}"

        header, packet, raw, remainder = parse_server_packet remainder

        receive_packet header, packet
      end while remainder.size > 0 && header > 0 && !@authenticated

      @buffer << remainder

      connection_reestablished remainder if @authenticated
    end

    def send_client_data data
      client.send_data data
    end

    def connection_reestablished data
      send_client_data data
      @client.connection_reestablished
    end

    def unbind
      client.server_unbound
      close_connection
    end
  end
end