require 'tmpdir'
require 'zip/zip'

class ImportError < StandardError; end
class ServerNotFoundError < StandardError; end

class ImportWorldJob
  @queue = :pc

  def self.perform(server_id, funpack_id, url, reply_key)
    @server_id = server_id
    @reply_key = reply_key

    @server = $mongo['servers'].find_one(_id: oid(server_id))
    raise ServerNotFoundError if @server.nil?

    funpack = Funpack.find(funpack_id)
    if funpack.nil?
      raise ImportError, "No funpack found for #{funpack_id}"
    end

    working_dir = File.join(
      Dir.tmpdir, Time.now.to_i.to_s, simplify(File.basename(url)))

    chdir(working_dir) do
      chdir('world') do
        info 'downloading_world', url: url
        restore_zip_archive(url)
      end

      chdir('funpack') do
        info 'downloading_funpack', funpack: funpack.url
        restore_archive(funpack.url)
      end

      i = funpack_import
      info 'world_info', i

      chdir('world') do
        # clean ./ from start of paths if necessary
        paths = i['paths'].map{|p| p.gsub(/^\.\//,'')}

        ts = Time.now

        key = "worlds/#{server_id}/#{server_id}.#{ts.to_i}.imported.tar.lzo"
        base = "https://party-cloud-#{Brain.env}.s3.amazonaws.com"
        import_url = "#{base}/#{key}"

        chdir(i['root']) do
          info 'uploading_world', url: import_url
          run("#{Brain.root}/bin/archive-dir", import_url, paths.map{|p| quote(p)}.join(' '))
        end

        snapshot_id = save_snapshot(server_id, import_url, ts)
        reply(:success, snapshot_id, import_url, i['settings'])
      end
    end
  rescue ImportError => e
    reply(e.message.to_s)

  rescue => e
    Brain.log.info(
      event: 'import_failed',
      error: e)

    reply("There was an error processing your file. Please contact support@minefold.com")
    raise
  end

  def self.reply(result, snapshot_id=nil, url=nil, settings=nil)
    Resque.push 'low', class: 'WorldImportedJob', args: [
      result,
      @server_id,
      snapshot_id.to_s,
      url,
      settings,
      @reply_key]
  end

  def self.save_snapshot(server_id, url, ts)
    snapshot = {
      created_at: ts,
      updated_at: ts,
      url: url
    }
    if parent = @server['snapshot_id']
      snapshot['parent'] = parent
    end

    snapshot_id = $mongo['snapshots'].insert(snapshot)

    $mongo['servers'].update({_id: oid(server_id)}, {
      '$set' => {
        updated_at: ts,
        snapshot_id: snapshot_id
      }
    })
    snapshot_id
  end

  def self.simplify(name)
    name.gsub(/([^a-zA-Z0-9])/, '_')
  end

  def self.bash_escape(arg)
    arg.gsub(/([^a-zA-Z0-9])/, "\\\\" + '\1')
  end

  def self.restore_zip_archive(url)
    local_tmp_file = File.join(Dir.tmpdir, "#{Time.now.to_i.to_s}.zip")
    `mkdir -p #{File.dirname(local_tmp_file)}`
    success = system "curl --globoff --silent -Lo '#{local_tmp_file}' #{bash_escape(url)}"
    if !success
      Brain.log.info(
        event: 'download_failed',
        url: url)
      raise StandardError, "failed to download #{url}"
    end
    unzip(local_tmp_file)
  end

  def self.restore_archive(url)
    run("#{Brain.root}/bin/restore-dir", url)
  end

  def self.funpack_import
    # env = [
    #   "BUNDLE_GEMFILE=#{pack_dir}/Gemfile",
    #   "GEM_PATH=/app/vendor/bundle/ruby/1.9.1",
    # ]

    JSON.load(run("funpack/bin/import"))
  rescue StandardError => e
    raise ImportError, "Failed to process world: #{JSON.load(e.message)['failed']}"
  end

  def self.run(cmd, *args)
    cmd_s = "#{cmd} #{args.join(' ')}"
    result = `#{cmd_s} 2>&1`
    if $?.exitstatus != 0
      Brain.log.info(event: 'command_failed', cmd: cmd_s, dir:`pwd`.strip, result: result)
      raise StandardError, result
    end
    result
  end

  def self.unzip(file)
    Zip::ZipFile.foreach(file)
      .select {|f| f.file? && !f.name.include?('__MACOSX') }
      .each {|f|
        FileUtils.mkdir_p(File.dirname(f.name))
        f.extract(f.name)
      }

  rescue => e
    Scrolls.log(
      at: 'import world',
      failed: 'unzip_failed',
      file: file,
      error: e
    )

    raise ImportError, "Couldn't read the Zip archive"
  end


  def self.chdir(dir)
    `mkdir -p #{dir}`
    Dir.chdir(dir) { yield }
  end

  def self.oid(id)
    BSON::ObjectId(id.to_s)
  end

  def self.info(event, args)
    Brain.log.info(args.merge(event: event, dir:`pwd`.strip))
  end

  def self.quote(s)
    %Q{"#{s}"}
  end

end