require 'rails_helper'

RSpec.describe ReservationBooking do
  let(:user) { create_user(name: '利用者A') }
  let(:item) { Item.create!(name: '貸出用端末A', usage_mode: 'reservation') }
  let(:start) { Time.zone.local(2026, 11, 2, 9) }
  let(:finish) { Time.zone.local(2026, 11, 2, 10) }

  around do |example|
    travel_to(Time.zone.local(2026, 10, 30, 12)) { example.run }
  end

  def book(target: item, owner: user, from: start, to: finish, **options)
    described_class.create!(actor: owner, item_ids: [target.id], starts_at: from, ends_at: to, **options).sole
  end

  it 'stores separate dates for the same user and excludes future bookings from immediate current usage' do
    first = book
    second = book(from: start + 7.days, to: finish + 7.days)
    expect(first.usage_kind).to eq('reservation')
    expect(first.created_by).to eq(user)
    expect(second).not_to eq(first)
    expect(item.reload.current_usage).to be_nil
    expect(first.reservation_state).to eq(:scheduled)
  end

  [[9, 10], [8, 11], [9.5, 9.75], [8, 9.5], [9.5, 11]].each do |from_hour, to_hour|
    it "rejects overlapping periods #{from_hour} through #{to_hour}, even for the owner" do
      book
      from = start.beginning_of_day + from_hour.hours
      to = start.beginning_of_day + to_hour.hours
      expect { book(from: from, to: to) }.to raise_error(described_class::Invalid, /重複/)
      expect(Usage.count).to eq(1)
    end
  end

  it 'allows adjacent bookings on both boundaries and intervals spanning midnight' do
    book
    book(from: start - 1.hour, to: start)
    book(from: finish, to: finish + 1.hour)
    book(from: start.end_of_day.change(usec: 0) - 29.minutes - 59.seconds, to: start.beginning_of_day + 1.day + 1.hour)
    expect(Usage.count).to eq(4)
  end

  it 'uses server time for now and cannot extend past a following reservation' do
    now = Time.current
    book(from: now + 30.minutes, to: now + 1.hour)
    usage = book(from: 1.year.ago, to: now + 30.minutes, immediate: true)
    expect(usage.starts_at).to eq(now)
    expect(usage.reservation_state).to eq(:active)
    expect(usage.grace_period?(now: usage.ends_at)).to be(false)
    expect do
      described_class.update!(usage.id, actor: user, starts_at: usage.starts_at, ends_at: now + 40.minutes)
    end.to raise_error(described_class::Invalid, /重複/)
    expect(usage.reload.ends_at).to eq(now + 30.minutes)
  end

  it 'rolls back every row when a later target conflicts or has a required reason missing' do
    other = Item.create!(name: '貸出用端末B', usage_mode: 'reservation', reason_policy: 'required')
    expect do
      described_class.create!(actor: user, item_ids: [item.id, other.id], starts_at: start, ends_at: finish)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(Usage.count).to eq(0)
    book(target: other, reason: '検証')
    expect do
      described_class.create!(actor: user, item_ids: [item.id, other.id], starts_at: start, ends_at: finish, reason: '検証')
    end.to raise_error(described_class::Invalid)
    expect(Usage.count).to eq(1)
  end

  it 'creates one row per selected target and applies their own reason policies' do
    other = Item.create!(name: '貸出用端末B', usage_mode: 'reservation', reason_policy: 'required')
    rows = described_class.create!(actor: user, item_ids: [other.id, item.id], starts_at: start, ends_at: finish, reason: '共同検証')
    expect(rows.map(&:item_id)).to eq([item.id, other.id].sort)
    expect(rows.find { |row| row.item_id == item.id }.reason).to be_nil
    expect(rows.find { |row| row.item_id == other.id }.reason).to eq('共同検証')
  end

  it 'allows only the owner or an independent usage manager to change another users bookings' do
    owner = create_user
    manager = create_user(usage_manager: true)
    admin = create_user(admin: true)
    usage = described_class.create!(actor: manager, user_id: owner.id, item_ids: [item.id], starts_at: start, ends_at: finish).sole
    expect(usage).to have_attributes(user: owner, created_by: manager, updated_by: manager)
    expect do
      described_class.cancel!(usage.id, actor: admin)
    end.to raise_error(described_class::Forbidden)
    change = described_class.update!(usage.id, actor: manager, starts_at: start - 1.hour, ends_at: finish + 1.hour)
    expect(change.previous['starts_at']).to eq(start)
    expect(usage.reload).to have_attributes(starts_at: start - 1.hour, updated_by: manager)
    described_class.cancel!(usage.id, actor: manager)
    expect(usage.reload.cancelled_by_name_snapshot).to eq(manager.name)
  end

  it 'rejects proxy registration by ordinary users and rechecks revoked manager rights' do
    other = create_user
    expect { book(user_id: other.id) }.to raise_error(described_class::Forbidden)
    manager = create_user(usage_manager: true)
    usage = book
    User.where(id: manager.id).update_all(usage_manager: false)
    expect { described_class.cancel!(usage.id, actor: manager) }.to raise_error(described_class::Forbidden)
  end

  it 'releases cancelled and early-finished periods while retaining their records and planned ends' do
    usage = book
    described_class.cancel!(usage.id, actor: user)
    replacement = book
    travel_to(start + 20.minutes)
    described_class.finish!(replacement.id, actor: user)
    book(from: Time.current, to: finish)
    expect(usage.reload.completion_label).to eq('予約取消')
    expect(replacement.reload.ends_at).to eq(finish)
    expect(replacement.finished_at).to eq(Time.current)
    expect(Usage.count).to eq(3)
  end

  it 'restricts cancellation to before start, freezes active start time and prevents changes after natural expiry' do
    usage = book
    travel_to(start)
    expect { described_class.cancel!(usage.id, actor: user) }.to raise_error(described_class::Invalid)
    expect do
      described_class.update!(usage.id, actor: user, starts_at: start - 1.hour, ends_at: finish)
    end.to raise_error(described_class::Invalid)
    travel_to(finish)
    expect { described_class.finish!(usage.id, actor: user) }.to raise_error(described_class::Invalid)
    expect(usage.reload.reservation_state).to eq(:completed)
    expect(Usage.history_at).to include(usage)
    expect(Usage.outstanding).not_to include(usage)
  end

  it 'preserves existing reason requirements when settings change' do
    item.update!(reason_policy: 'required')
    usage = book(reason: '検証')
    item.update!(reason_policy: 'none')
    expect do
      described_class.update!(usage.id, actor: user, starts_at: start, ends_at: finish + 1.hour, reason: '')
    end.to raise_error(ActiveRecord::RecordInvalid)
    described_class.update!(usage.id, actor: user, starts_at: start, ends_at: finish + 1.hour)
    expect(usage.reload.reason).to eq('検証')
  end

  it 'protects items and users with live bookings, allows cleanup while disabled, and preserves snapshots on deletion' do
    usage = book
    expect(item.update(usage_mode: 'immediate')).to be(false)
    expect(item.destroy).to be(false)
    expect(user.destroy).to be(false)
    item.reload.update!(disabled: true)
    expect { book(from: start + 1.day, to: finish + 1.day) }.to raise_error(described_class::Invalid)
    described_class.cancel!(usage.id, actor: user)
    item.reload.destroy!
    user.destroy!
    expect(usage.reload).to have_attributes(item_id: nil, user_id: nil, cancelled_by_id: nil,
                                           item_name_snapshot: '貸出用端末A', cancelled_by_name_snapshot: '利用者A')
  end

  it 'rejects invalid periods, inactive users, missing targets and duplicate targets without writing' do
    expect { book(from: 1.minute.ago, to: finish) }.to raise_error(described_class::Invalid)
    expect { book(to: start) }.to raise_error(described_class::Invalid)
    expect { book(from: nil) }.to raise_error(described_class::Invalid)
    expect do
      described_class.create!(actor: user, item_ids: [item.id, item.id], starts_at: start, ends_at: finish)
    end.to raise_error(described_class::Invalid)
    user.update!(disabled: true)
    expect { book }.to raise_error(described_class::Forbidden)
    expect(Usage.count).to eq(0)
  end
end
