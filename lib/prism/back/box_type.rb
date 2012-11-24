class BoxType
  attr_reader :id, :ram_mb, :ecus, :ami

    RAM_ALLOCATION = 0.9 # we'll allocate this much % ram
    RAM_PER_PLAYER = 128
    ECUS_PER_SLOT = ((ENV['ECUS_PER_SLOT'] and ENV['ECUS_PER_SLOT'].to_i) || 1)
    RAM_MB_PER_SLOT = ((ENV['RAM_MB_PER_SLOT'] and ENV['RAM_MB_PER_SLOT'].to_i) || 512)

    INSTANCE_PLAYER_BUFFER = 5 # needs to be space for 5 players to start a world on a box

    AMIS = {
      '64bit' => 'ami-1176c278',
        'HVM' => 'ami-8ff445e6'
    }

  def self.definitions
    [
      BoxType.new('m1.small', 1.7 * 1024, 1, AMIS['64bit']),
      BoxType.new('c1.xlarge', 7.0 * 1024, 20, AMIS['64bit']),
      BoxType.new('cc2.8xlarge', 60.5 * 1024, 88, AMIS['64bit']),
    ]
  end

  def self.find id
    definitions.find{|box_type| box_type.id == id }
  end

  def initialize id, ram_mb, ecus, ami
    @id, @ram_mb, @ecus, @ami = id, ram_mb, ecus, ami
  end

  def server_slots
    [(allocated_ram_mb / RAM_MB_PER_SLOT).floor,
     (ecus / ECUS_PER_SLOT).floor].min
  end

  def allocated_ram_mb
    (ram_mb * RAM_ALLOCATION)
  end

  def slot_size_mb
    (allocated_ram_mb / server_slots).round
  end

  def player_slots
    (allocated_ram_mb / RAM_PER_PLAYER).round
  end

  def players_per_slot
    [(player_slots / server_slots).ceil, 4].max
  end
end