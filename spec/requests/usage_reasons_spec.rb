require 'rails_helper'

RSpec.describe 'Usage reasons', type: :request do
  let(:user) { create_user }
  let(:item) { Item.create!(name: '貸出用端末A', reason_policy: 'required') }

  around do |example|
    travel_to(Time.zone.local(2026, 10, 30, 12, 0)) { example.run }
  end
  before { login(user) }

  it 'rejects missing reasons on the server and preserves invalid input for correction' do
    ['', '  ', "\n\t"].each do |reason|
      post update_status_path(item), params: { expires_at: '13:00', reason: reason }
      expect(response).to have_http_status(:unprocessable_content)
    end
    post update_status_path(item), params: { expires_at: '13:00', reason: 'あ' * 501 }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).at_css('textarea').text.delete_prefix("\n")).to eq('あ' * 501)
    expect(Usage.count).to eq(0)
    expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
  end

  it 'keeps an existing reason when policy changes and notifies all successful operations' do
    url = 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET'
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(url)
    notification = stub_request(:post, url).with do |request|
      JSON.parse(request.body)['blocks'][1]['text']['text'].include?('*利用理由*: 検証 &lt;作業&gt;')
    end.to_return(status: 200)
    post update_status_path(item), params: { expires_at: '13:00', reason: '  検証 <作業>  ' }
    expect(Usage.sole.reason).to eq('検証 <作業>')
    item.update!(reason_policy: 'none')
    post extend_status_path(item), params: { expires_at: '14:00' }
    post end_use_status_path(item)
    expect(notification).to have_been_requested.times(3)
    get usage_histories_path
    expect(response.body).to include('検証 &lt;作業&gt;')
  end

  it 'allows an optional empty reason, rejects input when disabled and does not affect legacy usage' do
    item.update!(reason_policy: 'none')
    post update_status_path(item), params: { expires_at: '13:00', reason: '入力不可' }
    expect(Usage.count).to eq(0)
    item.update!(reason_policy: 'optional')
    post update_status_path(item), params: { expires_at: '13:00' }
    expect(Usage.sole.reason).to be_nil
    item.update!(reason_policy: 'required')
    post extend_status_path(item), params: { expires_at: '14:00' }
    expect(response).to redirect_to(status_path)
    post end_use_status_path(item)
    expect(Usage.sole.finished_at).to be_present
  end

  it 'preserves the reason in server-side overnight confirmation' do
    travel_to(Time.zone.local(2026, 10, 30, 23, 50))
    post update_status_path(item), params: { expires_at: '00:10', reason: '夜間検証' }
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('input[name="reason"]')['value']).to eq('夜間検証')
    post update_status_path(item), params: { expires_at: '00:10', reason: '夜間検証', confirmed_expires_at: Time.zone.local(2026, 10, 31, 0, 10).iso8601 }
    expect(Usage.sole.reason).to eq('夜間検証')
  end
end
