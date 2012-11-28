class BoxType
  attr_reader :id, :ram_mb, :ecus
  
  def self.definitions
    [
      BoxType.new('m1.small', 1.7 * 1024, 1),
      BoxType.new('c1.xlarge', 7.0 * 1024, 20),
      BoxType.new('cc2.8xlarge', 60.5 * 1024, 88),
    ]
  end

  def self.find id
    definitions.find{|box_type| box_type.id == id }
  end

  def initialize id, ram_mb, ecus
    @id, @ram_mb, @ecus = id, ram_mb, ecus
  end
end