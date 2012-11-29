class Time
  def minutes_til(to_time)
    (((to_time - self).abs)/60).round
  end
end

