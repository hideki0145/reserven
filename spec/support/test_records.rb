module TestRecords
  def create_user(**attributes)
    User.create!({ name: 'テスト利用者', email: "user-#{SecureRandom.hex(4)}@example.com",
                   password: 'test-password', password_confirmation: 'test-password' }.merge(attributes))
  end
end
