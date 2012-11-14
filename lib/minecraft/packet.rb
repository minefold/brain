require 'minecraft/minecraft_string_io'

module Minecraft
  class Packet
    def initialize header, body = {}
      @header = header
      @definition = {
        :header => :byte
      }.merge(body)
    end

    def parse data
      values = {}
      MinecraftStringIO.open(data) do |io|
        @definition.each do |name, type|
          values[name] = io.read_field type
        end
      end
      values
    end
    
    def create options = {}
      packet = ""
      MinecraftStringIO.open(packet, 'w') do |io|
        io.write_field :byte, @header
        
        options.each do |name, value|
          if field = @definition[name]
            io.write_field field, value
          else
            raise "packet does not contain field=#{name} definition=#{@definition.inspect}"
          end
        end
      end
      packet
    end
  end
end