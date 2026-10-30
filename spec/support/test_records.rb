module TestRecords
  def create_usage(item:, user:, expires_at: 1.hour.from_now, active: true)
    usage = Usage.create!(item: item, user: user, starts_at: expires_at - 1.hour, ends_at: expires_at,
                          finished_at: active ? nil : expires_at, finish_reason: active ? nil : 'returned',
                          finished_by: active ? nil : user, finished_by_name_snapshot: active ? nil : user.name)
    item.association(:current_usage).reset
    usage
  end

  def create_user(**attributes)
    User.create!({ name: 'テスト利用者', email: "user-#{SecureRandom.hex(4)}@example.com",
                   password: 'test-password', password_confirmation: 'test-password' }.merge(attributes))
  end
end
