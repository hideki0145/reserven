require 'rails_helper'

RSpec.describe Status, type: :model do
  let(:user) { create_user }
  let(:item) { Item.create!(name: '会議室') }
  let(:status) { Status.create!(item: item, user: user, use_flg: true, expires_at: Time.current) }

  around do |example|
    travel_to(Time.zone.local(2026, 10, 27, 12, 0)) { example.run }
  end

  it 'applies the grace period from expiry up to, but excluding, 15 minutes' do
    expect(status).to be_grace_period
    travel 15.minutes
    expect(status).not_to be_grace_period
  end

  it 'has no grace period before the deadline' do
    status.update!(expires_at: 1.minute.from_now)
    expect(status).not_to be_grace_period
  end

  it 'sets and resets usage' do
    status.reset
    expect(status.reload.use_flg).to be(false)
    expect(status).not_to be_grace_period
    status.set(user.id, 30.minutes.from_now)
    expect(status.reload.use_flg).to be(true)
    expect(status.user_id).to eq(user.id)
    expect(status.expires_at).to eq(30.minutes.from_now)
  end

  it 'enforces a single status per item at the database level' do
    status
    expect do
      Status.create!(item: item, user: user, expires_at: 1.hour.from_now)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
