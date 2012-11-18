ROOT = File.expand_path "../..", __FILE__

EC2_SECRET_KEY="4VI8OqUBN6LSDP6cAWXUo0FM1L/uURRGIGyQCxvq"
EC2_ACCESS_KEY="AKIAJPN5IJVEBB2QE35A"
MAPPER = "~/code/minefold/pigmap/pigmap"
WORLDS_BUCKET = OLD_WORLDS_BUCKET = ENV['WORLDS_BUCKET'] || 'minefold-development-worlds'
INCREMENTAL_WORLDS_BUCKET = ENV['INCREMENTAL_WORLDS_BUCKET'] || 'minefold-development'

Fold.workers = :local
Fold.worker_user = ENV['USER']

# Storage.provider = Fog::Storage.new({
#   :provider      => :local,
#   :local_root    => "#{ROOT}/tmp/s3"
# })
Storage.provider = Fog::Storage.new({
  :provider                 => :aws,
  :aws_secret_access_key    => EC2_SECRET_KEY,
  :aws_access_key_id        => EC2_ACCESS_KEY
})

# ENV['RACK_ENV'] = 'production' # exceptional gem looks at this ENV
# Exceptional::Config.load("#{ROOT}/config/exceptional.yml")

TEST_PRISM="localhost"