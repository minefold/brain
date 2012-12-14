require 'prism/back/logger'

module Brain
  def self.env
    ENV['BRAIN_ENV'] || 'development'
  end

  def self.root
    ENV['BRAIN_ROOT'] || File.expand_path('../..', __FILE__)
  end
  
  def self.log
    @log ||= Brain::Logger.new
  end
end
