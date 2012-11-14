module Prism
  class Allocator
    attr_accessor :log

    def initialize pinkies
      @pinkies = pinkies
      @log = Brain::Logger.new
    end

    def start_options_for_new_world(player_slots_required)
      
      player_slots_required = [4, (player_slots_required || 4)].max

      if pinky = find_pinky_for_new_world(player_slots_required)
        slots_required = (player_slots_required / [pinky.box_type.players_per_slot, 4].max.to_f).ceil
        ram_required = slots_required * pinky.box_type.slot_size_mb
        
        start_options = {
          pinky_id: pinky.id,
          ram: { min: ram_required, max: ram_required },
          slots: slots_required
        }
      end
    end

    def find_pinky_for_new_world(player_slots_required)
      # use the bigger instance types first,
      # then use the instance with the least available slots

      candidates = @pinkies.select {|pinky|
        log.info event:'candidate',
          id: pinky.id,
          server_slots: pinky.server_slots_available,
          player_slots: pinky.player_slots_available

        (pinky.server_slots_available * pinky.box_type.players_per_slot) >= player_slots_required
      }.sort_by{|pinky| -pinky.box_type.server_slots }.
        sort_by{|pinky| pinky.server_slots_available }

      candidates.first if candidates.any?
    end
  end
end