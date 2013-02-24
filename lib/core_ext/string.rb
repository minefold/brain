class NilClass
  def blank?
    true
  end
end

class String
  def blank?
    self == ''
  end
end