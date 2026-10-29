require 'rails_helper'

RSpec.describe 'Initial administrator seeds', type: :model do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ADMIN_EMAIL').and_return('seed@example.com')
    allow(ENV).to receive(:[]).with('ADMIN_PASSWORD').and_return('test-seed-password')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ADMIN_EMAIL').and_return('seed@example.com')
    allow(ENV).to receive(:fetch).with('ADMIN_PASSWORD').and_return('test-seed-password')
  end

  it 'creates the administrator once without modifying it on subsequent runs' do
    expect { load Rails.root.join('db/seeds.rb') }.to change(User, :count).by(1)
    user = User.find_by!(email: 'seed@example.com')
    expect(user).to be_admin
    expect(user.authenticate('test-seed-password')).to eq(user)
    digest = user.password_digest
    expect { load Rails.root.join('db/seeds.rb') }.not_to change(User, :count)
    expect(user.reload.password_digest).to eq(digest)
  end

  it 'does not create any users when the password is missing' do
    allow(ENV).to receive(:[]).with('ADMIN_PASSWORD').and_return(nil)
    expect { load Rails.root.join('db/seeds.rb') }.not_to change(User, :count)
  end

  it 'finds an existing user when the environment email has whitespace or different capitalization' do
    user = create_user(email: 'seed@example.com')
    digest = user.password_digest
    allow(ENV).to receive(:[]).with('ADMIN_EMAIL').and_return(' Seed@Example.COM ')
    allow(ENV).to receive(:fetch).with('ADMIN_EMAIL').and_return(' Seed@Example.COM ')
    expect { load Rails.root.join('db/seeds.rb') }.not_to change(User, :count)
    expect(user.reload.password_digest).to eq(digest)
    expect(user).not_to be_admin
  end
end
