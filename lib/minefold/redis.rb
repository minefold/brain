module Minefold
  module Redis
    def redis
      @redis ||= begin
        uri = URI.parse(REDISTOGO_URL)
        ::Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
      end
    end
  end
end