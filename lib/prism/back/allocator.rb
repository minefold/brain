module Prism
  class Allocator
    RAM_MB_PER_SLOT = (
      (ENV['RAM_MB_PER_SLOT'] and ENV['RAM_MB_PER_SLOT'].to_i) || 512)
    ECUS_PER_SLOT = (
      (ENV['ECUS_PER_SLOT'] and ENV['ECUS_PER_SLOT'].to_i) || 1)
    RAM_ALLOCATION = (
      (ENV['RAM_ALLOCATION'] and ENV['RAM_ALLOCATION'].to_f) || 0.9)

    attr_accessor :log

    def initialize(pinkies)
      @pinkies = pinkies
      @log = Brain::Logger.new
    end

    def find_pinky_for_new_world(ram_required)
      # use the bigger instance types first, because we're reserving them
      # then use the oldest one so we minimise box usage

      candidates = pinky_allocations.select {|pinky|

        log.info(pinky.merge(event: 'candidate'))

        (pinky[:state] == 'up') &&
          (ram_required <= pinky[:unallocated_ram])

      }.sort_by{|pinky| -pinky[:total_ram] }.
        sort_by{|pinky| pinky[:started_at].to_i }

      candidates.first if candidates.any?
    end

    def pinky_allocations
      @pinkies.select{|p| p.box_type}.map do |pinky|
        box_type = pinky.box_type
        total_ram = (box_type.ram_mb * RAM_ALLOCATION)
        allocated_ram = pinky.servers.inject(0) do |sum, s|
          if s.ram_allocation > 0
            sum + s.ram_allocation
          else
            # TODO deprecate slots
            sum + s.slots * RAM_MB_PER_SLOT
          end
        end

        {
          id: pinky.id,
          state: pinky.state,
          total_ram: total_ram,
          unallocated_ram: total_ram - allocated_ram,
          started_at: pinky.started_at,
          free_ram: pinky.free_ram_mb
        }
      end
    end

    def allocated_ram_mb(box_type)
      (box_type.ram_mb * RAM_ALLOCATION)
    end

    def server_slots(box_type)
      [(allocated_ram_mb(box_type) / RAM_MB_PER_SLOT).floor,
       (box_type.ecus / ECUS_PER_SLOT).floor].min
    end

    def server_slots_available(pinky)
      server_slots(pinky.box_type) - pinky.servers.size
    end
  end
end