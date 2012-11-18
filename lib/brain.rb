module Brain

  def self.env
    ENV['BRAIN_ENV'] || 'development'
  end

  def self.root
    ENV['BRAIN_ROOT'] || File.expand_path('../..', __FILE__)
  end

end
