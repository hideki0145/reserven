require 'rails_helper'

RSpec.describe 'Slack notification layouts' do
  let(:owner) { User.new(id: 1, name: '利用者A') }
  let(:actor) { User.new(id: 2, name: '利用者A') }
  let(:item) { Item.new(name: '貸出用端末A') }
  let(:start) { Time.zone.local(2026, 11, 2, 9) }
  let(:usage) do
    Usage.new(user_id: owner.id, user_name_snapshot: owner.name, item_name_snapshot: item.name,
              starts_at: start, ends_at: start + 3.hours, reason: '共同検証のため',
              finished_at: start + 1.hour, cancelled_at: start - 1.day)
  end

  def body(payload)
    payload[:blocks].map { |block| block[:text][:text] }.join("\n\n")
  end

  it 'keeps immediate-use reasons separate and omits them from end notifications' do
    payload = SlackUsageNotification.build(event: :start, item: item, user: owner,
                                           expires_at: usage.ends_at, reason: usage.reason)
    expect(payload[:blocks].last[:text][:text]).to eq('*利用理由*: 共同検証のため')
    expect(payload[:blocks][1][:text][:text]).not_to include('利用理由')
    ended = SlackUsageNotification.build(event: :end, item: item, user: owner, reason: usage.reason)
    expect(ended.to_json).not_to include('利用理由', usage.reason)
  end

  it 'labels both extension deadlines explicitly across dates' do
    payload = SlackUsageNotification.build(event: :extend, item: item, user: owner,
      previous_expires_at: usage.ends_at, expires_at: usage.ends_at + 1.day)
    expect(body(payload)).to include('*延長前の利用期限*: 11/02(月) 12:00', '*延長後の利用期限*: 11/03(火) 12:00')
  end

  it 'identifies proxy operators by ID rather than name' do
    proxy = ReservationNotification.build(event: :create, usages: [usage], actor: actor)
    expect(body(proxy)).to include('*操作者*: 利用者A')
    expect(proxy[:text]).to include('操作者: 利用者A')
    owner.name = '変更後の名前'
    own = ReservationNotification.build(event: :create, usages: [usage], actor: owner)
    expect(own.to_json).not_to include('操作者', '登録者')
  end

  it 'adds event-specific emoji and omits reasons only for finish' do
    { create: '📅', start: '🔵', update: '📝', cancel: '❌', finish: '✅' }.each do |event, emoji|
      payload = ReservationNotification.build(event: event, usages: [usage], actor: owner)
      expect(payload[:blocks].first[:text][:text]).to start_with("#{emoji} *")
      expect(payload[:text]).to start_with(emoji)
      if event == :finish
        expect(payload.to_json).not_to include(usage.reason, '利用理由')
      else
        expect(payload[:blocks].last[:text][:text]).to eq('*利用理由*: 共同検証のため')
      end
    end
  end

  it 'shows compact before/after periods and added, removed or changed reasons' do
    [nil, '接続確認のため'].product([nil, '共同検証のため']).each do |before_reason, after_reason|
      usage.reason = after_reason
      payload = ReservationNotification.build(event: :update, usages: [usage], actor: owner,
        previous: { 'starts_at' => start, 'ends_at' => start + 2.hours, 'reason' => before_reason })
      expect(body(payload)).to include('*変更前の利用期間*: 2026/11/02(月) 09:00 ～ 11:00',
                                      '*変更後の利用期間*: 2026/11/02(月) 09:00 ～ 12:00')
      if before_reason != after_reason
        expect(body(payload)).to include("*変更前の利用理由*: #{before_reason || '(なし)'}",
                                        "*変更後の利用理由*: #{after_reason || '(なし)'}")
      end
    end
  end
end

RSpec.describe UsagePeriod do
  it 'abbreviates the end according to the local date and year' do
    start = Time.zone.local(2026, 11, 2, 9)
    expect(described_class.format(start, start + 3.hours)).to eq('2026/11/02(月) 09:00 〜 12:00')
    expect(described_class.format(start, start + 1.day)).to eq('2026/11/02(月) 09:00 〜 11/03(火) 09:00')
    expect(described_class.format(start, Time.zone.local(2027, 1, 1, 12))).to eq('2026/11/02(月) 09:00 〜 2027/01/01(金) 12:00')
    expect(described_class.format(Time.utc(2026, 12, 31, 15), Time.utc(2026, 12, 31, 16))).to eq('2027/01/01(金) 00:00 〜 01:00')
  end
end
