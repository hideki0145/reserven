require 'rails_helper'

RSpec.describe 'Period reservation screens', type: :request do
  let(:user) { create_user(name: '利用者A') }
  let(:item) { Item.create!(name: '貸出用端末A', usage_mode: 'reservation') }

  around do |example|
    travel_to(Time.zone.local(2026, 10, 30, 12)) { example.run }
  end

  before { login(user) }

  def input(**values)
    { timing: 'future', item_ids: [item.id], starts_at: '2026-11-02T09:00', ends_at: '2026-11-02T10:00' }.merge(values)
  end

  it 'registers a batch with one Slack notification and notifies individual changes and cancellation' do
    other = Item.create!(name: '貸出用端末B', usage_mode: 'reservation', reason_policy: 'required')
    url = 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET'
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(url)
    notifications = []
    request = stub_request(:post, url).with { |req| notifications << JSON.parse(req.body); true }.to_return(status: 200)
    post reservations_path, params: { reservation: input(item_ids: [item.id, other.id], reason: '共同検証') }
    expect(response).to redirect_to(reservations_path)
    expect(Usage.reservations.count).to eq(2)
    expect(request).to have_been_requested.once
    expect(notifications.first['blocks'][1]['text']['text']).to include(item.name, other.name, user.name)
    usage = Usage.reservations.find_by!(item: other)
    patch reservation_path(usage), params: { reservation: input(starts_at: '2026-11-02T08:00', ends_at: '2026-11-02T11:00', reason: '変更後の検証') }
    expect(response).to redirect_to(reservations_path)
    expect(notifications.last['blocks'].map { |block| block['text']['text'] }.join).to include('変更前', '変更後', '共同検証', '変更後の検証')
    patch cancel_reservation_path(usage)
    expect(usage.reload.cancelled_at).to be_present
    expect(request).to have_been_requested.times(3)
    expect(Usage.find_by!(item: item).cancelled_at).to be_nil
  end

  it 'keeps submitted values and commits nothing on conflicts or invalid dates' do
    ReservationBooking.create!(actor: user, item_ids: [item.id], starts_at: Time.zone.local(2026, 11, 2, 9), ends_at: Time.zone.local(2026, 11, 2, 10))
    post reservations_path, params: { reservation: input }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('重複', '2026/11/02(月)', 'value="2026-11-02T09:00"')
    expect(Usage.count).to eq(1)
    ['2026-02-30T09:00', '2026-11-02T24:00', 'not-a-date'].each do |date|
      post reservations_path, params: { reservation: input(starts_at: date) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Usage.count).to eq(1)
    end
    expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
  end

  it 'authorizes proxy operations independently of system administration and ignores forged owner updates' do
    other = create_user
    post reservations_path, params: { reservation: input(user_id: other.id) }
    expect(response).to have_http_status(:forbidden)
    manager = create_user(usage_manager: true)
    login(manager)
    post reservations_path, params: { reservation: input(user_id: user.id) }
    usage = Usage.sole
    expect(usage).to have_attributes(user: user, created_by: manager)
    login(other)
    get edit_reservation_path(usage)
    expect(response).to have_http_status(:forbidden)
    patch cancel_reservation_path(usage)
    expect(response).to have_http_status(:forbidden)
    login(user)
    patch reservation_path(usage), params: { reservation: input(user_id: other.id, ends_at: '2026-11-02T11:00') }
    expect(usage.reload.user_id).to eq(user.id)
    expect(usage.updated_by).to eq(user)
  end

  it 'uses server time for now, permits an exact active start when editing, and frees an early finish' do
    post reservations_path, params: { reservation: input(timing: 'now', starts_at: 'invalid', ends_at: '2026-10-30T13:00') }
    expect(response).to redirect_to(status_path)
    usage = Usage.sole
    expect(usage.starts_at).to eq(Time.current)
    patch reservation_path(usage), params: { reservation: { starts_at: usage.starts_at.iso8601(6), ends_at: '2026-10-30T14:00' } }
    expect(usage.reload.ends_at).to eq(Time.zone.local(2026, 10, 30, 14))
    patch finish_reservation_path(usage)
    expect(usage.reload.finished_at).to eq(Time.current)
    get status_path
    expect(response.body).to include('現在は空き', '今すぐ利用')
  end

  it 'shows current and next reservations on status while protecting existing immediate routes' do
    item
    get status_path
    expect(response.body).to include('予約して利用', '期間を指定して予約')
    expect(Nokogiri::HTML(response.body).css('.status-table tbody tr')).to be_empty
    post update_status_path(item), params: { expires_at: '13:00' }
    expect(Usage.count).to eq(0)
    post reservations_path, params: { reservation: input }
    get reservations_path(member: 'self')
    expect(response.body).to include('予約予定', item.name, '2026/11/02(月) 09:00')
    expect(Nokogiri::HTML(response.body).text).not_to match(/\d{2}:\d{2}:\d{2}/)
  end

  it 'keeps the committed batch when Slack fails and accepts no invalid or inactive targets' do
    url = 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET'
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(url)
    stub_request(:post, url).to_timeout
    post reservations_path, params: { reservation: input }
    expect(Usage.count).to eq(1)
    item.update!(disabled: true)
    post reservations_path, params: { reservation: input(starts_at: '2026-11-03T09:00', ends_at: '2026-11-03T10:00') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Usage.count).to eq(1)
  end

  it 'finds the next date rather than the oldest record ID without loading every future booking' do
    ReservationBooking.create!(actor: user, item_ids: [item.id], starts_at: Time.zone.local(2026, 12, 1, 9), ends_at: Time.zone.local(2026, 12, 1, 10))
    next_usage = ReservationBooking.create!(actor: user, item_ids: [item.id], starts_at: Time.zone.local(2026, 11, 1, 9), ends_at: Time.zone.local(2026, 11, 1, 10)).sole
    expect(Usage.next_reservations([item.id]).to_a).to eq([next_usage])
    get status_path
    expect(response.body).to include('2026/11/01')
    expect(response.body).not_to include('2026/12/01')
  end

  it 'shows the next owner and authorizes current reservation actions directly from status' do
    owner = create_user(name: '予約利用者B')
    usage = ReservationBooking.create!(actor: owner, item_ids: [item.id], immediate: true, ends_at: 1.hour.from_now).sole
    ReservationBooking.create!(actor: user, item_ids: [item.id], starts_at: 2.hours.from_now, ends_at: 3.hours.from_now)
    get status_path
    panel = Nokogiri::HTML(response.body).at_css('.reservation-panel')
    expect(panel.text).to include('次の予約:', "利用者: #{user.name}(自分)", '2026/10/30(金)')
    expect(panel.css('a').map { |a| a.text }).not_to include('期間・理由の変更')
    expect(panel.css('input[type=submit], button').map { |b| b['value'] || b.text }).not_to include('利用終了')
    patch finish_reservation_path(usage), params: { return_to: 'status' }
    expect(response).to have_http_status(:forbidden)
    manager = create_user(usage_manager: true)
    login(manager)
    get status_path
    expect(response.body).to include(edit_reservation_path(usage, return_to: 'status'))
    get edit_reservation_path(usage, return_to: 'status')
    expect(response.body).to include('name="return_to"', 'value="status"')
    patch reservation_path(usage), params: { return_to: 'status', reservation: { starts_at: usage.starts_at.iso8601(6), ends_at: '2026-10-30T13:30' } }
    expect(response).to redirect_to(status_path)
    expect(usage.reload.updated_by).to eq(manager)
    patch finish_reservation_path(usage), params: { return_to: 'status' }
    expect(response).to redirect_to(status_path)
    expect(usage.reload.finished_by).to eq(manager)
  end

  it 'keeps status context through invalid edits and never redirects to a submitted URL' do
    post reservations_path, params: { reservation: input(timing: 'now', ends_at: '2026-10-30T13:00') }
    usage = Usage.sole
    patch reservation_path(usage), params: { return_to: 'status', reservation: { starts_at: usage.starts_at.iso8601(6), ends_at: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('name="return_to"', 'value="status"')
    patch finish_reservation_path(usage), params: { return_to: 'https://example.com' }
    expect(response).to redirect_to(reservations_path)
  end

  it 'marks the current navigation group on root, child and filtered pages' do
    user.update!(admin: true)
    paths = { root_path => '利用状況', status_path => '利用状況', usage_histories_path(member: 'self') => '利用履歴',
              new_reservation_path => '予約一覧', admin_users_path => 'ユーザ一覧', edit_admin_user_path(user) => 'ユーザ一覧',
              reorder_admin_users_path => 'ユーザ一覧', new_admin_item_path => '利用設定一覧', reorder_admin_items_path => '利用設定一覧' }
    paths.each do |path, label|
      get path
      links = Nokogiri::HTML(response.body).css('#app-navigation a[aria-current="page"]')
      expect(links.map(&:text)).to eq([label]), path
      expect(links.first['class']).to include('active')
    end
  end

  [
    ['2026-10-31T15:30', '2026-10-31T16:20', '2026/10/31(土) 15:30 〜 16:20'],
    ['2026-10-31T15:30', '2026-11-01T16:20', '2026/10/31(土) 15:30 〜 11/01(日) 16:20'],
    ['2026-12-31T15:30', '2027-01-01T16:20', '2026/12/31(木) 15:30 〜 2027/01/01(金) 16:20']
  ].each do |start, finish, expected|
    it "uses the same compact usage period in reservations and history: #{expected}" do
      post reservations_path, params: { reservation: input(starts_at: start, ends_at: finish) }
      expect(response).to redirect_to(reservations_path)
      usage = Usage.sole
      get reservations_path
      html = Nokogiri::HTML(response.body)
      expect(html.css('thead th')[1].text).to eq('利用期間')
      expect(html.css('tbody tr td')[1].text).to eq(expected)
      travel_to(usage.ends_at + 1.minute)
      get usage_histories_path
      html = Nokogiri::HTML(response.body)
      expect(html.css('thead th')[1].text).to eq('利用期間')
      expect(html.css('tbody tr td')[1].text).to eq(expected)
    end
  end

  it 'restores the start reference for a missing immediate start without filling a required future start' do
    post reservations_path, params: { reservation: input(timing: 'now', starts_at: nil, ends_at: '2026-10-30T11:00') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).at_css('#reservation_starts_at')['value']).to eq('2026-10-30T12:15')
    expect(Usage.count).to eq(0)
    post reservations_path, params: { reservation: input(starts_at: '') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).at_css('#reservation_starts_at')['value']).to be_blank
    expect(Usage.count).to eq(0)
  end

end
