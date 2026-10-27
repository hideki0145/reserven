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

  it 'removes dependent statuses when a user is deleted' do
    user = create_user
    item = Item.create!(name: '会議室')
    Status.create!(user: user, item: item, expires_at: 1.hour.from_now)
    expect { user.destroy! }.to change(Status, :count).by(-1)
  end
end
