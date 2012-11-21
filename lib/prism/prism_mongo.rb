require 'logging'

module Prism
  module Mongo
    extend Logging

    def mongo_connect
      @connection ||= begin
        uri = ENV['MONGO_URL'] || 'mongodb://localhost:27017'
        mongo = ::Mongo::Connection.from_uri(uri)

        if mongo.is_a? ::Mongo::ReplSetConnection
          # this should be in the damn ruby driver
          mongo_uri = ::Mongo::URIParser.new(uri)
          auth = mongo_uri.auths.first

          db = mongo[auth['db_name']]
          db.authenticate auth['username'], auth['password']
          db
        else
          db_name = mongo.auths.any? ? mongo.auths.first['db_name'] : 'minefold'
          mongo[db_name]
        end
      end
    end
  end
end

