require 'yaml'
require 'prism/back'

class GameServerUpdater
  include Prism::Mongo

  def initialize game
    @game = game
  end

  def name
    @game['name']
  end

  def update
    @game['versions'].each do |game_version|
      version_name, url = game_version['name'], game_version['url']

      headers = http_headers(url)
      etag = headers['ETag']

      version_name = game_version['name']
      unless stored_version?(etag)
        local_file = download game_version['url'], "tmp/#{version_name}/#{etag}/server.jar"

        if version_name == 'HEAD'
          detected_version = detect_server_version local_file
          puts "detected #{name} #{version_name} #{detected_version}"
        else
          detected_version = version_name
        end

        upload local_file, "#{name}/#{detected_version}/server.jar"

        store_server detected_version, etag, Time.parse(headers['Last-Modified'])
      end
    end
    puts mongo['game_servers'].find_one({:name => @game['name']}).to_yaml
  end

  def store_server version, etag, created_at
    version_info = {
      'name' => version,
      'etag' => etag,
      'created_at' => created_at
    }

    mongo['game_servers'].update({
      name: 'minecraft'
    }, {
      '$push' => { 'versions' => version_info }
    }, upsert: true)
    puts "saved #{version_info.inspect}"
  end

  def detect_server_version file
    version_line = 'minecraft server version'
    version_string = `unzip -p #{file} | strings | grep '#{version_line}'`.strip
    raise "Version matched more than one line:\n#{version_string}" if version_string.include? "\n"
    matches = version_string.match(/version\s+(.*)/)
    raise 'Unable to extract version' unless matches.size > 1
    matches[1]
  end

  def download url, local_file
    puts "downloading new #{name} server #{local_file}"
    FileUtils.mkdir_p File.dirname(local_file)
    puts `curl --silent --show-error -L '#{url}' -o #{local_file}`
    local_file
  end

  def upload local_file, remote_file
    puts "uploading #{remote_file}"
    bucket = Storage.game_servers

    bucket.upload local_file, remote_file, public: false
  end

  def stored_version? etag
    stored_servers and stored_servers['versions'].any?{|v| v['etag'] == etag }
  end

  def http_headers url
    `curl -IL --silent --show-error '#{url}'`.strip.split("\n").each_with_object({}) do |line, h|
      if line.include? ':'
        key, value = line.split(':', 2)
        h[key] = value.strip.gsub('"', '')
      end
    end
  end

  def mongo
    @mongo ||= mongo_connect
  end

  def stored_servers
    @stored_servers ||= mongo['game_servers'].find_one({:name => @game['name']})
  end
end