require 'fog'

class Storage
  class << self; attr_accessor :provider; end

  def self.old_worlds
    retry_timeout, retry_times = 1, 0
    begin
      new provider.directories.create(:key => OLD_WORLDS_BUCKET, :public => false)
    rescue => e
      puts "failed #{retry_times} times: #{e}\n#{e.backtrace.join("\n")}"
      sleep retry_timeout
      retry_timeout += 1
      retry_times += 1
      retry if (retry_times < 10)
      raise e
    end
  end

  def self.worlds
    retry_timeout, retry_times = 1, 0
    begin
      new provider.directories.create(:key => WORLDS_BUCKET, :public => false)
    rescue => e
      puts "failed #{retry_times} times: #{e}\n#{e.backtrace.join("\n")}"
      sleep retry_timeout
      retry_timeout += 1
      retry_times += 1
      retry if (retry_times < 10)
      raise e
    end
  end
  
  def self.incremental_worlds
    retry_timeout, retry_times = 1, 0
    begin
      new provider.directories.create(:key => INCREMENTAL_WORLDS_BUCKET, :public => false)
    rescue => e
      puts "failed #{retry_times} times: #{e}\n#{e.backtrace.join("\n")}"
      sleep retry_timeout
      retry_timeout += 1
      retry_times += 1
      retry if (retry_times < 10)
      raise e
    end
  end

  def self.game_servers
    new provider.directories.create(:key => "minefold-runpacks", :public => false)
  end

  attr_reader :directory

  def initialize directory
    @directory = directory
  end
  
  def exists? remote_file
    directory.files.head(remote_file)
  end

  def download remote_file, local_file
    key = nil
    File.open(local_file, File::RDWR|File::CREAT) do |local|
      key = directory.files.get(remote_file) do |chunk, remaining_bytes, total_bytes|
        local.write chunk
      end
    end
    local_file if key
  end

  def upload local_file, remote_file, options = {}
    File.open(local_file) do |file|
      directory.files.create({key: remote_file, body: file}.merge(options))
    end
  end
end