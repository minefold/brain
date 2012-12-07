# TODO store in database

class Funpack < Struct.new(:id, :url, :client_version, :bump_message)
  def self.find(id)
    all.find{|f| f.id == id }
  end

  def self.all
    base_url = 'https://party-cloud-production.s3.amazonaws.com/funpacks/slugs'
    @funpacks ||= [
      Funpack.new(
        '50a976ec7aae5741bb000001',
        "#{base_url}/minecraft/stable.tar.lzo",
        nil, nil),
      Funpack.new(
        '50a976fb7aae5741bb000002',
        "#{base_url}/minecraft-essentials/stable.tar.lzo",
        nil, nil),
      Funpack.new(
        '50a977097aae5741bb000003',
        "#{base_url}/tekkit/stable.tar.lzo",
        "1.2.5", "This server requires a Tekkit client: http://www.technicpack.net/tekkit/"),
      Funpack.new(
        '50bec3967aae5797c0000004',
        "#{base_url}/team-fortress-2/stable.tar.lzo",
        nil, nil),
    ]
  end
end
