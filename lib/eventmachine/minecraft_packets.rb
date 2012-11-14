module EventMachine
  module Protocols
    module Minecraft
      module Packets
        def self.hex num
          "0x%02X" % num
        end

        def self.easy_fields
          { byte:[1, "C"], short:[2, "n"], int:[4, "N"], long:[8, "Q"], float:[4, "g"], double:[8, "G"] }
        end

        def self.pack_field type, value
          byte_size, code = easy_fields[type]
          if code
            [value].pack code
          else
            case type
            when :string8
              [value.length, value.encode('UTF-8')].pack("na*")
            when :string16
              [value.length, value.encode('UTF-16BE')].pack("na*")
            when :bool
              [value ? 0 : 1].pack("C")
            else
              raise "Unknown field type #{type}"
            end
          end
        end

        def self.read_field type, packet, index
          byte_size, code = easy_fields[type]
          if code
            [packet[index..(index + byte_size)].unpack(code)[0], byte_size]
          else
            case type
            when :string8
              str_char_length, bytes_read = read_field :short, packet, index; index += bytes_read
              str_byte_length = (str_char_length)
              raw = packet[index..(index + str_byte_length)]
              value = raw.force_encoding('UTF-8').encode('UTF-8')
              [value, 2 + str_byte_length]
            when :string16
              str_char_length, bytes_read = read_field :short, packet, index; index += bytes_read
              str_byte_length = (str_char_length * 2)
              raw = packet[index..(index + str_byte_length - 1)]
              value = raw.force_encoding('UTF-16BE').encode('UTF-8')

              [value, 2 + str_byte_length]
            when :bool
              value, bytes_read = read_field(:byte, packet, index); index += bytes_read
              [value == 1, bytes_read]
            when :metadata
              total_bytes_read = 0
              begin
                value, bytes_read = read_field(:byte, packet, index); index += bytes_read
                total_bytes_read += bytes_read
              end while value != 0x7f
              ["...", total_bytes_read]
            when :inventory_payload
              count, bytes_read = read_field :short, packet, index; index += bytes_read
              count.times {
                item_id, bytes_read = read_field :short, packet, index; index += bytes_read
                if item_id != -1
                  count, bytes_read = read_field :byte, packet, index; index += bytes_read
                  count, bytes_read = read_field :short, packet, index; index += bytes_read
                end
              }
              "..."
            else
              raise "Unknown field type #{type}"
            end
          end
        end

        def self.create_packet schema, header, values
          data = pack_field(:byte, header)
          schema.each{|name, type|
            raise "no value provided for #{name}" unless values[name]
            data << pack_field(type, values[name])
          }
          data
        end

        def self.parse_packet schemas, packet
          # null if packet not long enough otherwise the parsed info plus the rest of the packet
          i = 0
          header, bytes_read = read_field :byte, packet, i; i += bytes_read

          schema = schemas[header]

          raise "Unknown packet:#{hex(header)}" unless schema

          body = schema.inject({}) do |hash, (name, type)|
            value, bytes_read = read_field type, packet, i; i += bytes_read
            hash[name] = value
            hash
          end

          [header, body, packet[0...i], packet[i..-1] || ""]
        end

        # these are the originators. ie. client sent a client packet, server sent a server packet
        module Client
          def self.client header, schema = {}
            client_packet_schemas[header] = schema
          end

          def client_packet header, values = {}
            Packets.create_packet Client.client_packet_schemas[header], header, values
          end

          def parse_client_packet data
            Packets.parse_packet Client.client_packet_schemas, data
          end

          def self.client_packet_schemas
            @@client_schemas ||= {}
          end

          client 0x00, :keepalive_id => :int
          client 0x01, :protocol_version => :int,
                       :username => :string16,
                       :unused1 => :string16,
                       :unused2 => :int,
                       :unused3 => :int,
                       :unused4 => :byte,
                       :unused5 => :byte,
                       :unused6 => :byte
          client 0x02, :username => :string16
          client 0x07, :user => :int, :target => :int, :left_click => :bool
          client 0x09, :world => :byte, :difficulty => :byte, :creative_mode => :byte, :world_height => :short, :map_seed => :long
          client 0x0A, :on_ground => :bool
          client 0x0B, :x => :double, :y => :double, :stance => :double, :z => :double, :on_ground => :bool
          client 0x0C, :yaw => :float, :pitch => :float, :on_ground => :bool
          client 0x0D, :x => :double, :y => :double, :stance => :double, :z => :double, :yaw => :float, :pitch => :float, :on_ground => :bool
          client 0x0E, :status => :byte, :x => :int, :y => :byte, :z => :int, :face => :byte
          client 0x0F, :x => :int, :y => :byte, :z => :int, :direction => :byte, :item_id => :short, :amount => :byte, :damage => :short
          client 0x10, :slot_id => :short
          client 0x13, :eid => :int, :action_id => :byte
          client 0xFE
          client 0xFF, :reason => :string16

        end

        module Server
          def self.server header, schema = {}
            server_packet_schemas[header] = schema
          end

          def server_packet header, values = {}
            Packets.create_packet Server.server_packet_schemas[header], header, values
          end

          def parse_server_packet data
            Packets.parse_packet Server.server_packet_schemas, data
          end


          def self.server_packet_schemas
            @@server_schemas ||= {}
          end

          server 0x00, :keepalive_id => :int
          server 0x01, :entity_id => :int, :unknown => :string16, :map_seed => :long, :server_mode => :int, :dimension => :byte, :difficulty => :byte, :world_height => :byte, :max_players => :byte
          server 0x02, :connection_hash => :string16
          server 0x04, :time => :long
          server 0x05, :entity_id => :int, :slot => :short, :item_id => :short, :unknown => :short
          server 0x06, :x => :int, :y => :int, :z => :int
          server 0x08, :health => :short, :food => :short, :food_saturation => :float
          server 0x09, :world => :byte, :difficulty => :byte, :creative_mode => :byte, :world_height => :short, :map_seed => :long
          server 0x12, :eid => :int, :animate => :byte
          server 0x14, :eid => :int, :player_name => :string16, :x => :int, :y => :int, :z => :int, :rotation => :byte, :pitch => :byte, :current_item => :short
          server 0x15, :eid => :int, :item => :short, :count => :byte, :damage => :short, :x => :int, :y => :int, :z => :int, :rotation => :byte, :pitch => :byte, :roll => :byte
          server 0x16, :eid => :int, :eid => :int
          server 0x17, :eid => :int, :type => :byte, :x => :int, :y => :int, :z => :int, :eid => :int, :unknown1 => :short, :unknown2 => :short, :unknown3 => :short
          server 0x18, :eid => :int, :type => :byte, :x => :int, :y => :int, :z => :int, :yaw => :byte, :pitch => :byte, :data_stream => :metadata
          server 0x19, :eid => :int, :title => :string16, :x => :int, :y => :int, :z => :int, :direction => :int
          server 0x1A, :eid => :int, :x => :int, :y => :int, :z => :int, :count => :short
          server 0x1C, :eid => :int, :x => :short, :y => :short, :z => :short
          server 0x1D, :eid => :int
          server 0x1E, :eid => :int
          server 0x1F, :eid => :int, :dx => :byte, :dy => :byte, :dz => :byte
          server 0x20, :eid => :int, :yaw => :byte, :pitch => :byte
          server 0x21, :eid => :int, :dx => :byte, :dy => :byte, :dz => :byte, :yaw => :byte, :pitch => :byte
          server 0x22, :eid => :int, :x => :int, :y => :int, :z => :int, :yaw => :byte, :pitch => :byte
          server 0x26, :eid => :int, :status => :byte
          server 0x27, :eid => :int, :vehicle_id => :int
          server 0x28, :eid => :int, :metadata => :metadata
          server 0x29, :eid => :int, :effect_id => :byte, :amplifier => :byte, :duration => :short
          server 0x2B, :xp => :byte, :level => :byte, :total_xp => :short
          server 0x32, :x => :int, :z => :int, :mode => :bool, :x => :int, :y => :int, :z => :int, :yaw => :byte, :pitch => :byte, :metadata => :metadata
          server 0x33, :x => :int, :y => :short, :z => :int, :size_x => :byte, :size_y => :byte, :size_z => :byte, :compressed_size => :int, :compressed_data => :byte_array
          server 0x34, :chunk_x => :int, :chunk_z => :int, :array_size => :short, :coord_array => :short_array, :type_array => :byte_array, :metadata_array => :byte_array
          server 0x35, :x => :int, :y => :byte, :z => :int, :block_type => :byte, :block_metadata => :byte
          server 0x36, :x => :int, :y => :short, :z => :int, :byte1 => :byte, :byte2 => :byte
          server 0x3C, :x => :double, :y => :double, :z => :double, :unknown => :float, :record_count => :int, :x => :byte, :y => :byte, :z => :byte
          server 0x3D, :effect_id => :int, :x => :int, :y => :byte, :z => :int, :sound_data => :int
          server 0x46, :reason => :byte, :game_mode => :byte
          server 0x47, :eid => :int, :unknown => :bool, :x => :int, :y => :int, :z => :int
          server 0x64, :window_id => :byte, :type => :byte, :title => :string16, :slots => :byte
          server 0x65, :window_id => :byte
          server 0x67, :window_id => :byte, :slot => :short, :item_id => :short, :item_count => :byte, :item_uses => :short
          server 0x68, :window_id => :byte, :payload => :inventory_payload
          server 0x69, :window_id => :byte, :progress_bar => :short, :value => :short
          server 0x6A, :window_id => :byte, :action_number => :short, :accepted => :bool

          server 0xFF, :reason => :string16

        end
      end
    end
  end
end