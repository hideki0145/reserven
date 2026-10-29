require 'rails_helper'
require Rails.root.join('db/migrate/20261029000000_normalize_user_emails')

RSpec.describe NormalizeUserEmails, type: :model do
  it 'normalizes existing emails without changing account data or timestamps' do
    user = create_user
    described_class::UserRecord.where(id: user.id).update_all(email: ' Legacy@Example.COM ')
    original = user.reload.attributes.except('email')
    described_class.new.migrate(:up)
    expect(user.reload.email).to eq('legacy@example.com')
    expect(user.attributes.except('email')).to eq(original)
  end

  it 'rejects collisions before modifying any records' do
    first = create_user
    second = create_user
    described_class::UserRecord.where(id: first.id).update_all(email: ' Collision@Example.COM ')
    described_class::UserRecord.where(id: second.id).update_all(email: 'collision@example.com')
    expect { described_class.new.migrate(:up) }
      .to raise_error(ActiveRecord::MigrationError, /対象ID: #{first.id}, #{second.id}/)
    expect(first.reload.email).to eq(' Collision@Example.COM ')
    expect(second.reload.email).to eq('collision@example.com')
  end
end
