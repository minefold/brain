require 'eventmachine/minecraft_packets'

module EventMachine
  module Protocols
    module Minecraft
      include Packets::Server
      include Packets::Client

      def receive_packet header, packet; end
      def parse_packet data; end
      def create_packet header, body; end

      def receive_data data
        @buffer ||= ''
        remainder = @buffer + data
        @buffer = ''

        begin
          header, packet, raw, remainder = parse_packet remainder

          receive_packet header, packet
        end while remainder.size > 0 && header > 0

        @buffer << remainder
      end

      def send_packet header, body = {}
        pkt = create_packet(header, body)
        p " > #{header} #{body.inspect}  #{pkt}"
        send_data pkt
      end

      module Client
        include EM::P::Minecraft

        def parse_packet data
          parse_server_packet data
        end

        def create_packet header, body
          client_packet header, body
        end
      end

      module Server
        include EM::P::Minecraft

        def parse_packet data
          parse_client_packet data
        end

        def create_packet header, body
          server_packet header, body
        end
      end
    end
  end
end
