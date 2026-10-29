require 'rails_helper'

RSpec.describe Item, type: :model do
  it 'requires a name' do
    expect(Item.new(name: '')).not_to be_valid
    expect(Item.new(name: '会議室')).to be_valid
  end

  context 'usage state and permitted actions' do
    let(:owner) { create_user }
    let(:other) { create_user }
    let(:item) { Item.create!(name: '貸出PC') }

    around do |example|
      travel_to(Time.zone.local(2026, 10, 29, 12, 0)) { example.run }
    end

    def expect_usage(viewer, state, start:, extend:, finish:)
      expect(item.usage_state(viewer.id)).to eq(state)
      expect(item.can_start_usage?(viewer.id)).to eq(start)
      expect(item.can_extend_usage?(viewer.id)).to eq(extend)
      expect(item.can_end_usage?(viewer.id)).to eq(finish)
    end

    it 'allows starting unused items, including ones with ended usage' do
      expect_usage(owner, :available, start: true, extend: false, finish: false)
      item.create_status!(user: owner, use_flg: false, expires_at: 1.hour.ago)
      expect_usage(owner, :available, start: true, extend: false, finish: false)
      expect_usage(other, :available, start: true, extend: false, finish: false)
    end

    it 'reserves active usage for the owner' do
      item.create_status!(user: owner, use_flg: true, expires_at: 1.minute.from_now)
      expect_usage(owner, :in_use, start: false, extend: true, finish: true)
      expect_usage(other, :in_use, start: false, extend: false, finish: false)
    end

    it 'uses one clock reading even when the deadline passes during a state check' do
      deadline = Time.current
      viewer_id = other.id
      item.create_status!(user: owner, use_flg: true, expires_at: deadline)
      allow(Time).to receive(:current).and_return(deadline - 0.001, deadline + 0.001)
      expect(item.usage_state(viewer_id)).to eq(:in_use)
      expect(Time).to have_received(:current).once
    end

    it 'keeps state and start permission consistent with a shared time at the grace boundary' do
      deadline = 15.minutes.ago
      item.create_status!(user: owner, use_flg: true, expires_at: deadline)
      checked_at = deadline + 15.minutes - 0.001
      expect(item.usage_state(other.id, now: checked_at)).to eq(:grace_period)
      expect(item.can_start_usage?(other.id, now: checked_at)).to be(false)
      checked_at = deadline + 15.minutes
      expect(item.usage_state(other.id, now: checked_at)).to eq(:available)
      expect(item.can_start_usage?(other.id, now: checked_at)).to be(true)
    end

    [0, 899, 900, 901].each do |seconds|
      it "handles both viewers #{seconds} seconds after expiry" do
        item.create_status!(user: owner, use_flg: true, expires_at: seconds.seconds.ago)
        grace = seconds < 900
        expect_usage(owner, grace ? :grace_period : :expired, start: false, extend: true, finish: true)
        expect_usage(other, grace ? :grace_period : :available, start: !grace, extend: false, finish: false)
      end
    end

    it 'allows only the owner to finish stopped usage regardless of expiry' do
      item.update!(disabled: true)
      expect_usage(owner, :stopped, start: false, extend: false, finish: false)
      item.create_status!(user: owner, use_flg: true, expires_at: 1.hour.ago)
      expect_usage(owner, :stopped, start: false, extend: false, finish: true)
      expect_usage(other, :stopped, start: false, extend: false, finish: false)
      item.status.reset
      expect_usage(owner, :stopped, start: false, extend: false, finish: false)
    end
  end

  it 'removes its dependent status when deleted' do
    item = Item.create!(name: '会議室')
    Status.create!(item: item, user: create_user, expires_at: 1.hour.from_now)
    expect { item.destroy! }.to change(Status, :count).by(-1)
  end
end

RSpec.describe 'Item deletion protection', type: :model do
  it 'keeps outstanding usage intact when deletion is rejected directly' do
    item = Item.create!(name: '貸出PC')
    status = Status.create!(item: item, user: create_user, use_flg: true, expires_at: 1.hour.from_now)
    expect(item.destroy).to be(false)
    expect(status.reload.use_flg).to be(true)
  end
end
