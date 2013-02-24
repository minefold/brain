class Hash
  def merge_val key, value
    self[key] = value unless (value.to_s || '').empty?
  end
end
