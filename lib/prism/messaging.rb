module Prism
  module Messaging
    def self.registrations
      @registrations ||= Hash.new {|h,k| h[k] = {}}
    end

    def self.deliver_message channel, message
      registrations[channel].each do |recipient, blk|
        registrations[channel].delete recipient
        blk.call message
      end
    end

    def listen_once_json channel, *a, &b
      cb = EM::Callback *a, &b
      Prism::Messaging.registrations[channel][self] = proc {|message| cb.call JSON.parse(message) }
      cb
    end

    def listen_once channel, &blk
      Prism::Messaging.registrations[channel][self] = proc {|message| blk.call message }
    end

    def cancel_listener channel
      Prism::Messaging.registrations[channel].delete self
    end
  end
end
