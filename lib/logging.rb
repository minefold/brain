module Logging
  %w(error warn info debug).each do |level|
    define_method(:"#{level}") do |*args|
      tagged_message level, *args
    end
  end

  def tagged_message level, *args
    message = args.last

    instance_tags = Array(self.class.log_tag_symbols)
    instance_tag_part = " " + instance_tags.map {|tag, h| "#{tag}:#{instance_variable_get(:"@#{tag}")}" }.join(' ') if instance_tags.any?

    method_tags = Array(args[0..-2])
    method_tag_part = method_tags.join('') if method_tags.any?

    puts "[#{level.upcase}]#{instance_tag_part}#{method_tag_part} #{message}"
  end

  def self.included klass
    klass.extend ClassMethods
  end

  module ClassMethods
    attr_reader :log_tag_symbols

    def log_tags *tags
      @log_tag_symbols = tags
    end
  end
end