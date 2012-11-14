class UserMailer
  @queue = :mailer

  def self.credit_reminder user_id
    Resque.enqueue self, "credit_reminder", user_id
  end
end

