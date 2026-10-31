require 'rails_helper'

RSpec.describe 'Usage management settings and immediate proxy operations', type: :request do
  it 'lets only system administrators configure modes and independent manager permissions' do
    user = create_user
    item = Item.create!(name: '貸出用端末A')
    login(user)
    patch admin_user_path(user), params: { user: { usage_manager: true } }
    expect(user.reload.usage_manager?).to be(false)
    login(create_user(admin: true))
    patch admin_user_path(user), params: { user: { usage_manager: true } }
    expect(user.reload.usage_manager?).to be(true)
    patch admin_item_path(item), params: { item: { usage_mode: 'reservation' } }
    expect(item.reload.usage_mode).to eq('reservation')
  end

  it 'allows managers to extend and finish others immediate usage and records both people in Slack' do
    owner = create_user(name: '利用者A')
    manager = create_user(name: '利用担当B', usage_manager: true)
    item = Item.create!(name: '貸出用端末A')
    usage = item.start_usage!(owner, 30.minutes.from_now)
    login(manager)
    url = 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET'
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(url)
    request = stub_request(:post, url).with do |req|
      JSON.parse(req.body)['blocks'][1]['text']['text'].include?("*利用者*: #{owner.name}\n*操作者*: #{manager.name}")
    end.to_return(status: 200)
    deadline = 1.hour.from_now
    post extend_status_path(item), params: { usage_id: usage.id, expires_at: deadline.iso8601, confirmed_expires_at: deadline.iso8601 }
    expect(usage.reload.updated_by).to eq(manager)
    post end_use_status_path(item), params: { usage_id: usage.id }
    expect(usage.reload.finished_by).to eq(manager)
    expect(request).to have_been_requested.times(2)
  end

  it 'rejects a stale proxy form after a different usage takes over' do
    owner = create_user
    manager = create_user(usage_manager: true)
    other = create_user
    item = Item.create!(name: '貸出用端末A')
    previous = item.start_usage!(owner, 30.minutes.from_now)
    previous.finish!(owner)
    current = item.reload.start_usage!(other, 1.hour.from_now)
    login(manager)
    post end_use_status_path(item), params: { usage_id: previous.id }
    expect(flash[:alert]).to include('利用状況が変わった')
    expect(current.reload.finished_at).to be_nil
    post extend_status_path(item), params: { usage_id: previous.id, expires_at: 2.hours.from_now.iso8601 }
    expect(flash[:alert]).to include('利用状況が変わった')
    expect(current.reload.updated_by).to eq(other)
    expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
  end

  it 'clears a session if the account becomes inactive immediately before an operation' do
    user = create_user
    item = Item.create!(name: '貸出用端末A')
    login(user)
    allow_any_instance_of(User).to receive(:reload).and_wrap_original do |original, *args|
      User.where(id: user.id).update_all(disabled: true) if original.receiver.id == user.id
      original.call(*args)
    end
    post update_status_path(item), params: { expires_at: '13:00' }
    expect(response).to redirect_to(login_path)
    expect(Usage.count).to eq(0)
  end
end
