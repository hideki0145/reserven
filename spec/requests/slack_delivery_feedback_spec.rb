require 'rails_helper'

RSpec.describe 'Slack delivery feedback', type: :request do
  let(:url) { 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET' }
  before do
    login(create_user)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(url)
  end

  it 'preserves an immediate start, extension and finish while displaying the final delivery failure' do
    notification = stub_request(:post, url).to_return(status: 503)
    item = Item.create!(name: '貸出用端末A')
    deadline = 1.hour.from_now.change(sec: 0)
    post update_status_path(item), params: { expires_at: deadline.iso8601, confirmed_expires_at: deadline.iso8601 }
    usage = Usage.sole
    expect(response).to redirect_to(status_path)
    expect(flash[:alert]).to include('操作は保存されましたが、Slack通知を送信できませんでした')
    get status_path
    expect(response.body).to include('同じ操作を繰り返さず')
    deadline += 1.hour
    post extend_status_path(item), params: { usage_id: usage.id, expires_at: deadline.iso8601, confirmed_expires_at: deadline.iso8601 }
    expect(usage.reload.ends_at).to eq(deadline)
    expect(flash[:alert]).to include('Slack通知を送信できませんでした')
    post end_use_status_path(item), params: { usage_id: usage.id }
    expect(usage.reload.finished_at).not_to be_nil
    expect(flash[:alert]).to include('Slack通知を送信できませんでした')
    expect(notification).to have_been_requested.times(6)
    expect(Usage.count).to eq(1)
  end

  it 'does not show a failure if a retry succeeds' do
    notification = stub_request(:post, url).to_return(status: 503).then.to_return(status: 200)
    item = Item.create!(name: '貸出用端末A', usage_mode: 'reservation')
    post reservations_path, params: { reservation: { timing: 'future', item_ids: [item.id],
      starts_at: 1.day.from_now.strftime('%Y-%m-%dT%H:%M'), ends_at: 2.days.from_now.strftime('%Y-%m-%dT%H:%M') } }
    expect(response).to redirect_to(reservations_path)
    expect(flash[:alert]).to be_nil
    expect(notification).to have_been_requested.twice
    expect(Usage.count).to eq(1)
  end
end
