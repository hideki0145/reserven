require 'rails_helper'

RSpec.describe User, type: :model do
  it 'authenticates the password and rejects an incorrect password' do
    user = create_user
    expect(user.authenticate('test-password')).to eq(user)
    expect(user.authenticate('incorrect')).to be(false)
  end

  it 'requires a name, a unique email and a password' do
    user = create_user
    invalid = User.new(email: user.email)
    expect(invalid).not_to be_valid
    expect(invalid.errors.attribute_names).to include(:name, :email, :password)
  end

  it 'creates, verifies and revokes a remember token' do
    user = create_user
    user.create_remember_digest
    expect(user.authenticated?(user.remember_token)).to be(true)
    expect(user.authenticated?('incorrect')).to be(false)
    expect(user.authenticated?(nil)).to be(false)
    user.delete_remember_digest
    expect(user.reload.authenticated?(user.remember_token)).to be(false)
  end

  it 'normalizes email on creation, update and lookup' do
    user = create_user(email: '  First@Example.COM  ')
    expect(user.reload.email).to eq('first@example.com')
    expect(User.find_by(email: ' FIRST@EXAMPLE.COM ')).to eq(user)
    user.update!(email: '  Next@Example.COM  ')
    expect(user.reload.email).to eq('next@example.com')
  end

  it 'rejects duplicate emails after normalization on creation and update' do
    user = create_user(email: 'duplicate@example.com')
    duplicate = User.new(name: '重複', email: ' Duplicate@Example.COM ', password: 'test-password')
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to be_present
    other = create_user
    expect(other.update(email: " #{user.email.upcase} ")).to be(false)
    expect(other.errors[:email]).to be_present
  end

  it 'rejects blank and missing emails after normalization' do
    [nil, '   '].each do |email|
      user = User.new(name: '利用者', email: email, password: 'test-password')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end
  end

  it 'removes dependent statuses when a user is deleted' do
    user = create_user
    item = Item.create!(name: '会議室')
    Status.create!(user: user, item: item, expires_at: 1.hour.from_now)
    expect { user.destroy! }.to change(Status, :count).by(-1)
  end
end

RSpec.describe 'Last active administrator protection', type: :model do
  it 'rejects direct model changes and keeps dependent usage intact on rejected deletion' do
    admin = create_user(admin: true)
    item = Item.create!(name: 'PC')
    status = Status.create!(item: item, user: admin, use_flg: true, expires_at: 1.hour.from_now)
    expect(admin.update(admin: false)).to be(false)
    admin.reload
    expect(admin.update(disabled: true)).to be(false)
    admin.reload
    expect(admin.destroy).to be(false)
    expect(status.reload.use_flg).to be(true)
  end
end
