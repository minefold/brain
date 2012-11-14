class Session < Model
  collection :sessions

  def self.sanitize username
    username.downcase.strip
  end

  %w(player_id
     world_id
     started_at
     minutes_played
  ).each do |field|
    define_method(:"#{field}") do
      @doc[field]
    end
  end
end