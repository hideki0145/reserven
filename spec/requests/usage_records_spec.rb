require 'rails_helper'

RSpec.describe 'Immediate usage records', type: :request do
  let(:user) { create_user(name: '利用者A') }
  let(:item) { Item.create!(name: '貸出用端末A') }

  around do |example|
    travel_to(Time.zone.local(2026, 10, 29, 12, 0)) { example.run }
  end

  before { login(user) }

  it 'keeps the same record for extension and finish, and adds a record for a later start' do
    post update_status_path(item), params: { expires_at: '12:30' }
    usage = Usage.sole
    expect(usage).to have_attributes(item: item, user: user, starts_at: Time.current, ends_at: 30.minutes.from_now)
    travel 5.minutes
    post extend_status_path(item), params: { expires_at: '13:00' }
    expect(Usage.count).to eq(1)
    expect(usage.reload).to have_attributes(starts_at: 5.minutes.ago, ends_at: Time.zone.local(2026, 10, 29, 13))
    post end_use_status_path(item)
    expect(usage.reload).to have_attributes(finished_at: Time.current, finish_reason: 'returned', finished_by: user)
    expect(item.reload.current_usage).to be_nil
    travel 5.minutes
    post update_status_path(item), params: { expires_at: '13:30' }
    expect(Usage.count).to eq(2)
    expect(item.reload.current_usage).not_to eq(usage)
    expect(usage.reload.finished_at).to eq(5.minutes.ago)
  end

  it 'records a takeover separately from an explicit return' do
    post update_status_path(item), params: { expires_at: '12:30' }
    previous = Usage.sole
    other = create_user(name: '利用者B')
    travel 45.minutes
    login(other)
    post update_status_path(item), params: { expires_at: '13:30' }
    expect(previous.reload).to have_attributes(finish_reason: 'reassigned', finished_at: Time.current, finished_by: other)
    expect(item.reload.current_usage.user).to eq(other)
    expect(Usage.count).to eq(2)
    login(user)
    post end_use_status_path(item)
    expect(item.reload.current_usage).to be_unfinished
  end

  it 'creates no record for invalid, unconfirmed or conflicting operations' do
    ['', 'invalid', '00:10'].each { |value| post update_status_path(item), params: { expires_at: value } }
    expect(Usage.count).to eq(0)
    post update_status_path(item), params: { expires_at: '12:30' }
    login(create_user)
    post update_status_path(item), params: { expires_at: '13:00' }
    post extend_status_path(item), params: { expires_at: '13:00' }
    post end_use_status_path(item)
    expect(Usage.count).to eq(1)
    expect(Usage.sole).to be_unfinished
  end

  it 'sends no Slack notification if saving the usage fails' do
    allow_any_instance_of(Usage).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    expect(SlackNotifier).not_to receive(:deliver)
    post update_status_path(item), params: { expires_at: '12:30' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Usage.count).to eq(0)
    expect(item.reload.current_usage).to be_nil
  end

  it 'keeps the recorded usage when Slack fails' do
    url = 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET'
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(url)
    stub_request(:post, url).to_timeout
    post update_status_path(item), params: { expires_at: '12:30' }
    expect(response).to redirect_to(status_path)
    expect(item.reload.current_usage).to eq(Usage.sole)
  end
end
