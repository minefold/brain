module StatsD
  def self.increment_and_measure_from start_time, key
    measure_timer start_time, key
    increment_counter key
  end

  def self.increment_counter key
    StatsD.increment "counters.#{key}"
  end

  def self.measure_timer start_time, key
    time = Time.now - start_time
    ms = time * 1000
    StatsD.measure key, ms
  end
end