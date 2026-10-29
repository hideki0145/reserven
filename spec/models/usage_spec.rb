require 'rails_helper'

RSpec.describe Usage, type: :model do
  let(:user) { create_user(name: '利用者A') }
  let(:item) { Item.create!(name: '貸出用端末A') }

  around do |example|
    travel_to(Time.zone.local(2026, 10, 29, 12, 0)) { example.run }
  end

  it 'requires a valid period and captures the names at creation' do
    usage = Usage.new(item: item, user: user, starts_at: Time.current, ends_at: Time.current)
    expect(usage).not_to be_valid
    usage.ends_at = 1.hour.from_now
    usage.save!
    expect(usage).to have_attributes(item_name_snapshot: item.name, user_name_snapshot: user.name)
  end

  it 'applies grace from the deadline up to, but excluding, fifteen minutes' do
    usage = create_usage(item: item, user: user, expires_at: Time.current)
    expect(usage.grace_period?(now: usage.ends_at - 0.001)).to be(false)
    expect(usage.grace_period?(now: usage.ends_at)).to be(true)
    expect(usage.grace_period?(now: usage.ends_at + 15.minutes)).to be(false)
    usage.finish!(user)
    expect(usage.grace_period?(now: usage.ends_at)).to be(false)
  end

  it 'retains finished usage and snapshots after names change and related records are deleted' do
    usage = item.start_usage!(user, 1.hour.from_now)
    item.update!(name: '変更後の名前')
    user.update!(name: '変更後の利用者')
    usage.finish!(user)
    item.reload.destroy!
    user.destroy!
    expect(usage.reload).to have_attributes(item_id: nil, user_id: nil, finished_by_id: nil,
                                           item_name_snapshot: '貸出用端末A', user_name_snapshot: '利用者A',
                                           finished_by_name_snapshot: '変更後の利用者')
  end

  it 'rolls back closing the old usage if the replacement cannot be created' do
    old = create_usage(item: item, user: user, expires_at: 30.minutes.ago)
    expect do
      item.start_usage!(create_user, Time.current)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(old.reload).to be_unfinished
    expect(Usage.where(item: item).count).to eq(1)
  end

  it 'keeps past usage when multiple sessions are recorded for the same item' do
    first = item.start_usage!(user, 30.minutes.from_now)
    first.finish!(user)
    item.reload
    second = item.start_usage!(user, 1.hour.from_now)
    expect(first.reload).not_to be_unfinished
    expect(item.reload.current_usage).to eq(second)
    expect(item.usages.count).to eq(2)
  end
end
