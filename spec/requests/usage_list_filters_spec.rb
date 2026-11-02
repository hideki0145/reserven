require 'rails_helper'

RSpec.describe 'History and reservation filter choices', type: :request do
  around { |example| travel_to(Time.zone.local(2026, 11, 1, 10)) { example.run } }
  let(:viewer) { create_user }
  let(:owner) { create_user(name: '利用者B') }
  let(:active) { Item.create!(name: '貸出用端末A', usage_mode: 'reservation') }
  let(:stopped) { Item.create!(name: '貸出用端末B', usage_mode: 'reservation') }
  before { login(viewer) }

  def html
    Nokogiri::HTML(response.body)
  end

  def choices(name)
    html.css("select##{name} option").map(&:text)
  end

  def records
    html.css('.history-table tbody tr')
  end

  [:history, :reservations].each do |screen|
    context screen.to_s do
      let(:path) { screen == :history ? usage_histories_path : reservations_path }
      let(:target_value) { screen == :history ? "id:#{stopped.id}" : stopped.id.to_s }
      let(:member_value) { screen == :history ? "id:#{owner.id}" : owner.id.to_s }
      before do
        [active, stopped].each_with_index do |item, i|
          user = i.zero? ? viewer : owner
          if screen == :history
            create_usage(item: item, user: user, active: false)
          else
            ReservationBooking.create!(actor: user, item_ids: [item.id], starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)
          end
        end
        stopped.update!(disabled: true, seq: 0)
        owner.update!(disabled: true, seq: 0)
      end

      it 'limits choices to active records without hiding rows, and expands each selector independently' do
        get path
        expect(choices('target')).to include(active.name)
        expect(choices('target')).not_to include(/貸出用端末B/)
        expect(choices('member')).not_to include(/利用者B/)
        expect(records.length).to eq(2)
        get path, params: { include_inactive_targets: '1' }
        expect(choices('target')).to eq(['すべて', active.name, "#{stopped.name}(利用停止中)"])
        expect(choices('member')).not_to include(/利用者B/)
        expect(records.length).to eq(2)
        get path, params: { include_inactive_members: '1' }
        expect(choices('target')).not_to include(/貸出用端末B/)
        expect(choices('member')).to include("#{owner.name}(アカウント無効)")
        expect(records.length).to eq(2)
      end

      it 'keeps explicit bookmarked inactive filters visible and clears only a selector whose checkbox is turned off' do
        get path, params: { target: target_value, member: member_value }
        expect(records.length).to eq(1)
        expect(html.at_css('#target option[selected]')['value']).to eq(target_value)
        expect(html.at_css('#member option[selected]')['value']).to eq(member_value)
        expect(html.at_css('#include_inactive_targets')['checked']).not_to be_nil
        expect(html.at_css('#include_inactive_members')['checked']).not_to be_nil
        get path, params: { target: target_value, member: member_value, include_inactive_targets: '0', include_inactive_members: '1' }
        expect(html.at_css('#target option[selected]')).to be_nil
        expect(html.at_css('#member option[selected]')['value']).to eq(member_value)
        expect(records.length).to eq(1)
        get path, params: { include_inactive_targets: '0', include_inactive_members: '0', member: member_value }
        expect(html.at_css('#member option[selected]')).to be_nil
        expect(records.length).to eq(2)
      end

      it 'retains the include flags and inactive selections on page links and refresh links' do
        25.times do |i|
          if screen == :history
            create_usage(item: stopped, user: owner, active: false, expires_at: (i + 1).hours.ago)
          else
            Usage.create!(item: stopped, user: owner, usage_kind: 'reservation', starts_at: (i + 2).days.from_now, ends_at: (i + 2).days.from_now + 1.hour)
          end
        end
        get path, params: { target: target_value, member: member_value, include_inactive_targets: '1', include_inactive_members: '1' }
        link = html.at_css('a[href*="page=2"]')['href']
        expect(link).to include('include_inactive_targets=1', 'include_inactive_members=1')
        get link
        expect(records.length).to eq(1)
        expect(html.at_css('#target option[selected]')['value']).to eq(target_value)
        expect(html.at_css('#member option[selected]')['value']).to eq(member_value)
        if screen == :reservations
          refresh = html.css('a').find { |a| a.text == '更新' }['href']
          expect(refresh).to include('include_inactive_targets=1', 'include_inactive_members=1', 'page=2')
        end
      end
    end
  end

  it 'offers deleted snapshot names only on request and keeps them safely searchable' do
    item = Item.create!(name: '<b>過去の端末</b>')
    former = create_user(name: '<b>過去の利用者</b>')
    create_usage(item: item, user: former, active: false)
    item.destroy!
    former.destroy!
    get usage_histories_path
    expect(choices('target')).not_to include(/過去の端末/)
    expect(choices('member')).not_to include(/過去の利用者/)
    expect(records.length).to eq(1)
    get usage_histories_path, params: { include_inactive_targets: '1', include_inactive_members: '1', target: "name:#{item.name}", member: "name:#{former.name}" }
    expect(choices('target')).to include("#{item.name}(削除済み)")
    expect(choices('member')).to include("#{former.name}(削除済み)")
    expect(html.css('select b')).to be_empty
    expect(records.length).to eq(1)
    expect(html.at_css('#target option[selected]')['value']).to eq("name:#{item.name}")
  end
end
