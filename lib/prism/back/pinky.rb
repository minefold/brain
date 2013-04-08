module Prism
  class Pinky < Struct.new(:id, :started_at, :state, :free_disk_mb,
                          :free_ram_mb, :idle_cpu, :box_type, :servers)

    def up?
      state == :up
    end
  end

  # TODO deprecate slots
  class Server < Struct.new(:id, :ram_allocation, :slots)
  end
end