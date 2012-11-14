class MinecraftPlayer < Model
  FREE_MINUTES = 600

  collection :minecraft_players

  attr_accessor :user

  def self.upsert_by_username username, remote_ip, *a, &b
    cb = EM::Callback(*a, &b)

    slug = sanitize(username)

    # for new documents
    default_properties = {
      slug: slug,
      username: username,
      distinct_id: `uuidgen`.strip,
      created_at: Time.now,
      updated_at: Time.now,
      unlock_code: rand(36 ** 4).to_s(36),
      last_remote_ip: remote_ip
    }

    # for existing documents
    update_properties = {
      '$set' => {
        username: username,
        updated_at: Time.now,
        last_remote_ip: remote_ip
      }
    }

    query = { deleted_at: nil, slug: slug }
    find_one(query) do |player|
      new_record = player.nil?

      properties = new_record ? default_properties : update_properties

      find_and_modify(
        query: query,
        update: properties,
        upsert: true,
        new: true
      ) do |player|
        cb.call player, new_record
      end
    end

    cb
  end

  def self.find_with_user id, *a, &b
    cb = EM::Callback(*a, &b)
    find(id) do |player|
      if player.user_id
        User.find(player.user_id) do |u|
          player.user = u
          cb.call player
        end
      else
        cb.call player
      end
    end
  end

  def self.find_by_username_with_user username, *a, &b
    cb = EM::Callback(*a, &b)
    find_one(deleted_at: nil, slug: sanitize(username)) do |player|
      if player and player.user_id
        User.find(player.user_id) do |u|
          player.user = u
          cb.call player
        end
      else
        cb.call player
      end
    end
  end

  def self.upsert_by_username_with_user username, remote_ip, *a, &b
    cb = EM::Callback(*a, &b)
    upsert_by_username(username, remote_ip) do |player, new_record|
      if player.user_id
        User.find(player.user_id) do |u|
          player.user = u
          cb.call player, new_record
        end
      else
        cb.call player, new_record
      end
    end
  end


  def self.sanitize username
    username.downcase.strip
  end

  %w(user_id
     slug
     username
     distinct_id
     last_connected_at
     last_remote_ip
     minutes_played
  ).each do |field|
    define_method(:"#{field}") do
      @doc[field]
    end
  end

  def verified?
    not user.nil?
  end

  def has_credit?
    if user
      user.has_credit?
    else
      (minutes_played || 0) < FREE_MINUTES
    end
  end

  def credits
    if user
      user.credits
    else
      FREE_MINUTES - (minutes_played || 0)
    end
  end

  def limited_time?
    user.nil? or (user.limited_time?)
  end

  def plan_status
    if user
      user.plan_status
    else
      "#{FREE_MINUTES - (minutes_played || 0)} remaining"
    end
  end
end