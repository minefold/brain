module Prism
  class Pinky < Struct.new(:id, :state, :free_disk_mb,
                          :free_ram_mb, :idle_cpu, :box_type, :servers)

    def up?
      state == :up
    end

    def server_slots_available
      box_type.server_slots - servers.size
    end

    def player_slots_available
      # TODO players!

      players = []
      box_type.player_slots - players.size
    end
  end

  class Server < Struct.new(:id)
  end
end