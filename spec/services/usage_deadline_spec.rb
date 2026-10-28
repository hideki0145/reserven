require 'rails_helper'

RSpec.describe UsageDeadline do
  around do |example|
    travel_to(Time.zone.local(2026, 10, 28, 19, 30)) { example.run }
  end

  it 'uses today for a later time' do
    expect(described_class.parse('20:00')).to eq(Time.zone.local(2026, 10, 28, 20))
  end

  it 'uses tomorrow for an earlier time' do
    expect(described_class.parse('18:00')).to eq(Time.zone.local(2026, 10, 29, 18))
  end

  it 'rejects the current minute, including when seconds have elapsed' do
    now = Time.zone.local(2026, 10, 28, 19, 30, 45)
    expect { described_class.parse('19:30', now: now) }.to raise_error(UsageDeadline::Invalid, '現在と同じ時刻は指定できません。')
  end

  it 'rolls across month and year boundaries' do
    now = Time.zone.local(2026, 12, 31, 23, 55)
    expect(described_class.parse('00:10', now: now)).to eq(Time.zone.local(2027, 1, 1, 0, 10))
  end

  it 'keeps an explicit future date, including seconds and offsets' do
    ['2026-10-29T00:10', '2026-10-29 00:10', '2026-10-29T00:10:00+09:00', '2026-10-28T15:10:00Z'].each do |value|
      expect(described_class.parse(value)).to eq(Time.zone.local(2026, 10, 29, 0, 10))
    end
  end

  it 'rejects an explicit past or present date rather than rolling it forward' do
    ['2026-10-28T18:00', '2026-10-28T19:30', '2026-10-27T20:00'].each do |value|
      expect { described_class.parse(value) }.to raise_error(UsageDeadline::Invalid, '利用期限は現在より後の日時を指定してください。')
    end
  end

  [nil, '', ' '].each do |value|
    it "rejects a missing deadline: #{value.inspect}" do
      expect { described_class.parse(value) }.to raise_error(UsageDeadline::Invalid, '期限を指定してください。')
    end
  end

  ['invalid', '24:00', '20:60', '2026-02-30T20:00', '2026-10-29T25:00', '2026-10-29T20:00:60', ['20:00'], { time: '20:00' }].each do |value|
    it "rejects an invalid deadline: #{value.inspect}" do
      expect { described_class.parse(value) }.to raise_error(UsageDeadline::Invalid, '利用期限を正しい日時で指定してください。')
    end
  end
end
