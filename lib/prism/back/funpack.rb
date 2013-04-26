# TODO store in database
class AllocationFactors < Struct.new(:cpu, :ram, :players)
  def initialize(h)
    super(h.values_at(:cpu, :ram, :players))
  end
end

class Funpack < Struct.new(:id, :slug, :client_version, :bump_message, :allocation_factors)
  BASE_URL = 'https://party-cloud-production.s3.amazonaws.com/funpacks/slugs'

  def self.find(id)
    all.find{|f| f.id == id }
  end

  def url
    "#{BASE_URL}/#{id}.tar.gz"
  end

  def self.all
    @funpacks ||= [
      Funpack.new(
        '50a976ec7aae5741bb000001', 'minecraft',
        nil, nil,
        AllocationFactors.new(
          cpu: 0.5, ram: 0.6, players: 5
        )),

      Funpack.new(
        '50a976fb7aae5741bb000002', 'bukkit-essentials',
        nil, nil,
        AllocationFactors.new(
          cpu: 0.8, ram: 0.9, players: 5
        )),

      Funpack.new(
        '50a977097aae5741bb000003', 'tekkit',
        "1.2.5", "This server requires a Tekkit client: http://www.technicpack.net/tekkit/",
        AllocationFactors.new(
          cpu: 0.5, ram: 0.9, players: 5
        )
      ),

      Funpack.new(
        '5126be367aae5712a4000007', 'tekkit-lite',
        nil, nil,
        AllocationFactors.new(
          cpu: 0.5, ram: 0.9, players: 5
        )
      ),

      Funpack.new(
        '50bec3967aae5797c0000004', 'team-fortress-2',
        nil, nil,
        AllocationFactors.new(
          cpu: 0.5, ram: 1.0, players: 32
        )),

      Funpack.new(
        '512159a67aae57bf17000005', 'feed-the-beast-direwolf20',
        nil, nil,
        AllocationFactors.new(
          cpu: 0.5, ram: 0.9, players: 5
        )),

      Funpack.new(
        '5179c548fc99860002000001', 'minecraft-mojang',
        nil, nil,
        AllocationFactors.new(
          cpu: 1, ram: 1, players: 10
        )),

    ]
  end
end
