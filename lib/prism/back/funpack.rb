# TODO store in database
class AllocationFactors < Struct.new(:cpu, :ram, :players)
  def initialize(h)
    super(h.values_at(:cpu, :ram, :players))
  end
end

class Funpack < Struct.new(:id, :url, :client_version, :bump_message, :allocation_factors)
  def self.find(id)
    all.find{|f| f.id == id }
  end

  def self.all
    base_url = 'https://party-cloud-production.s3.amazonaws.com/funpacks/slugs'
    @funpacks ||= [
      Funpack.new(
        '50a976ec7aae5741bb000001',
        "#{base_url}/minecraft/stable.tar.lzo",
        nil, nil,
        AllocationFactors.new(
          cpu: 0.5, ram: 0.6, players: 5
        )),

      Funpack.new(
        '50a976fb7aae5741bb000002',
        "#{base_url}/minecraft-essentials/stable.tar.lzo",
        nil, nil,
        AllocationFactors.new(
          cpu: 0.8, ram: 0.9, players: 5
        )),

      Funpack.new(
        '50a977097aae5741bb000003',
        "#{base_url}/tekkit/stable.tar.lzo",
        "1.2.5", "This server requires a Tekkit client: http://www.technicpack.net/tekkit/",
        AllocationFactors.new(
          cpu: 0.5, ram: 0.9, players: 5
        )
      ),

      Funpack.new(
        '50bec3967aae5797c0000004',
        "#{base_url}/team-fortress-2/stable.tar.lzo",
        nil, nil,
        AllocationFactors.new(
          cpu: 0.5, ram: 1.0, players: 32
        )),

      Funpack.new(
        '512159a67aae57bf17000005',
        "#{base_url}/512159a67aae57bf17000005.tar.gz",
        nil, nil,
        AllocationFactors.new(
          cpu: 0.5, ram: 0.9, players: 5
        )),
    ]
  end
end
