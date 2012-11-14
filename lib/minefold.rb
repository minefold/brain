ENV['FOLD_ENV'] ||= 'development'

module Fold
  class << self
    attr_accessor :workers, :worker_tags, :worker_user

    def env
      ENV['FOLD_ENV'].to_sym
    end

    def region
      ENV['EC2_REGION'] || 'us-east-1'
    end

    def compute_cloud
      @@compute_cloud ||= Fog::Compute.new({
        :provider                 => 'AWS',
        :aws_secret_access_key    => EC2_SECRET_KEY,
        :aws_access_key_id        => EC2_ACCESS_KEY,
        :region                   => region
      })
    end

    def root
      @root ||= File.expand_path File.join File.dirname(__FILE__), '../'
    end
  end
end

$:.unshift File.join File.dirname(__FILE__), '../config'

require 'logging'
require 'minefold/minefold_db'
require 'minefold/redis'
require 'minefold/storage'
require 'jobs'
require "#{Fold.env}"
