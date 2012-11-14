module Prism
  module Back
    module PlayerConnection
      def reject_player username, reason, options = {}
        rejection = ({rejected: reason}).merge(options)

        redis.publish_json "players:connection_request:#{username}", rejection
      end
    end
  end
end