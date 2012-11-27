module Prism
  class Allocator
    RAM_MB_PER_SLOT = (
      (ENV['RAM_MB_PER_SLOT'] and ENV['RAM_MB_PER_SLOT'].to_i) || 512)
    ECUS_PER_SLOT = (
      (ENV['ECUS_PER_SLOT'] and ENV['ECUS_PER_SLOT'].to_i) || 1)
    RAM_ALLOCATION = (
      (ENV['RAM_ALLOCATION'] and ENV['RAM_ALLOCATION'].to_f) || 0.9)
    RAM_PER_PLAYER = (
      (ENV['RAM_PER_PLAYER'] and ENV['RAM_PER_PLAYER'].to_i) || 128)

    attr_accessor :log

    def initialize pinkies
      @pinkies = pinkies
      @log = Brain::Logger.new
    end

    def start_options_for_new_world(players_required)
      players_required = [4, (players_required || 4)].max

      if pinky = find_pinky_for_new_world(players_required)
        ram_required = pinky[:slots_required] * RAM_MB_PER_SLOT

        start_options = {
          pinky_id: pinky[:id],
          ram: { min: ram_required, max: ram_required },
          slots: pinky[:slots_required]
        }
      end
    end

    def find_pinky_for_new_world(players_required)
      # use the bigger instance types first,
      # then use the instance with the least available slots

      candidates = pinky_allocations(players_required).select {|pinky|

        log.info(pinky.merge(event: 'candidate'))

        pinky[:state] == 'up' and
          pinky[:slots_required] <= pinky[:slots_available]

      }.sort_by{|pinky| -pinky[:total_slots] }.
        sort_by{|pinky| pinky[:slots_available] }

      candidates.first if candidates.any?
    end

    def pinky_allocations(players_required)
      @pinkies.map do |pinky|
        {
          id: pinky.id,
          state: pinky.state,
          total_slots: server_slots(pinky.box_type),
          slots_available: server_slots_available(pinky),
          slots_required: (
            players_required.to_f / players_per_slot(pinky)
          ).ceil
        }
      end
    end

    def allocated_ram_mb box_type
      (box_type.ram_mb * RAM_ALLOCATION)
    end

    def server_slots box_type
      [(allocated_ram_mb(box_type) / RAM_MB_PER_SLOT).floor,
       (box_type.ecus / ECUS_PER_SLOT).floor].min
    end

    def server_slots_available pinky
      server_slots(pinky.box_type) - pinky.servers.size
    end

    def player_slots_available pinky
      player_slots(pinky) - pinky.players.size
    end

    def player_slots pinky
      (allocated_ram_mb(pinky.box_type) / RAM_PER_PLAYER).round
    end

    def players_per_slot pinky
      [(player_slots(pinky) / server_slots(pinky.box_type)).ceil, 4].max
    end
  end
end