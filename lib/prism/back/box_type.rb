class BoxType
  attr_reader :id, :ram_mb, :ecus, :ami

  AMIS = {
    '64bit' => 'ami-1176c278',
      'HVM' => 'ami-9f9213f6'
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
end