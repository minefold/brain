class Funpack < Struct.new(:id, :new_id, :slug, :client_version, :bump_message)
  BASE_URL = 'https://party-cloud-production.s3.amazonaws.com/funpacks/slugs'

  def self.find(id)
    all.find{|f| f.new_id == id }
  end

  def url
    "#{BASE_URL}/#{id}.tar.gz"
  end

  def self.all
    @funpacks ||= [
      Funpack.new(
        '50a976ec7aae5741bb000001', '9ed10c25-60ed-4375-8170-29f9365216a0', 'minecraft',
        nil, nil
      ),

      Funpack.new(
        '50a976fb7aae5741bb000002', 'c942cbc1-05b2-4928-8695-b0d2a4d7b452', 'bukkit-essentials',
        nil, nil
      ),

      Funpack.new(
        '50a977097aae5741bb000003', '4bfcf174-e630-43d4-a17a-3c0d1491bae4', 'tekkit',
        "1.2.5", "This server requires a Tekkit client: http://www.technicpack.net/tekkit/"
      ),

      Funpack.new(
        '5126be367aae5712a4000007', 'a3ef2208-65df-4bc0-934c-e80e1bd7914f', 'tekkit-lite',
        nil, nil
      ),

      Funpack.new(
        '50bec3967aae5797c0000004', '3fe55a6d-36fe-4e27-9ba3-1309e6405aa5', 'team-fortress-2',
        nil, nil
      ),

      Funpack.new(
        '512159a67aae57bf17000005', '2f203313-cc51-4ae2-88b5-9d35620d8ef2', 'feed-the-beast-direwolf20',
        nil, nil
      ),

      Funpack.new(
        '5179c548fc99860002000001', '162c669c-857b-4072-bf76-267f05ae8b6a', 'minecraft-mojang',
        nil, nil
      ),
    ]
  end
end
