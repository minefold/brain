module Prism
  class Allocator
    RAM_MB_PER_SLOT = (
      (ENV['RAM_MB_PER_SLOT'] and ENV['RAM_MB_PER_SLOT'].to_i) || 512)
    ECUS_PER_SLOT = (
      (ENV['ECUS_PER_SLOT'] and ENV['ECUS_PER_SLOT'].to_i) || 1)
    RAM_ALLOCATION = (
      (ENV['RAM_ALLOCATION'] and ENV['RAM_ALLOCATION'].to_f) || 0.9)

    attr_accessor :log

    def initialize pinkies
      @pinkies = pinkies
      @log = Brain::Logger.new
    end

    def start_options_for_new_server(slots)
      if pinky = find_pinky_for_new_world(slots)
        ram_required = slots * RAM_MB_PER_SLOT

        start_options = {
          pinky_id: pinky[:id],
          ram: { min: ram_required, max: ram_required },
          slots: slots
        }
      end
    end

    def find_pinky_for_new_world(slots_required)
      # use the bigger instance types first,
      # then use the oldest one so we minimise box usage

      candidates = pinky_allocations.select {|pinky|

        log.info(pinky.merge(event: 'candidate'))

        pinky[:state] == 'up' and
          slots_required <= pinky[:slots_available]

      }.sort_by{|pinky| -pinky[:total_slots] }.
        sort_by{|pinky| pinky[:started_at].to_i }

      candidates.first if candidates.any?
    end

    def pinky_allocations
      @pinkies.select{|p| p.box_type}.map do |pinky|
        {
          id: pinky.id,
          state: pinky.state,
          total_slots: server_slots(pinky.box_type),
          slots_available: server_slots_available(pinky),
          started_at: pinky.started_at
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
  end
end