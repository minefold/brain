class Hash
  def merge_val key, value
    self[key] = value unless (value || '').empty?
  end
end
