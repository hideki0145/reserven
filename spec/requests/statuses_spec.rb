require 'rails_helper'

RSpec.describe 'Item usage', type: :request do
  let(:user) { create_user }
  let(:other_user) { create_user }
  let(:item) { Item.create!(name: '会議室') }

  around do |example|
    travel_to(Time.zone.local(2026, 10, 27, 12, 0)) { example.run }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(nil)
    login(user)
  end

  def reserve(owner: user, expires_at: 30.minutes.from_now, use_flg: true)
    Status.create!(item: item, user: owner, expires_at: expires_at, use_flg: use_flg)
  end

  it 'starts, extends and ends usage' do
    expect { post update_status_path(item), params: { expires_at: '12:30' } }.to change(Status, :count).by(1)
    expect(response).to redirect_to(status_path)
    expect(item.reload.status.user).to eq(user)
    expect(item.status.expires_at).to eq(Time.zone.local(2026, 10, 27, 12, 30))
    post extend_status_path(item), params: { expires_at: '13:00' }
    expect(item.status.reload.expires_at).to eq(Time.zone.local(2026, 10, 27, 13))
    post end_use_status_path(item)
    expect(item.status.reload.use_flg).to be(false)
  end

  it 'rejects an empty deadline' do
    expect { post update_status_path(item), params: { expires_at: '' } }.not_to change(Status, :count)
    expect(flash[:notice]).to eq('期限を指定してください。')
  end

  it 'rejects taking an item already in use by another user' do
    status = reserve(owner: other_user)
    post update_status_path(item), params: { expires_at: '13:00' }
    expect(status.reload.user).to eq(other_user)
    expect(flash[:notice]).to include('既に使用中')
  end

  it 'rejects taking an item during its grace period' do
    status = reserve(owner: other_user, expires_at: 5.minutes.ago)
    post update_status_path(item), params: { expires_at: '13:00' }
    expect(status.reload.user).to eq(other_user)
  end

  it 'allows taking an item after its grace period' do
    status = reserve(owner: other_user, expires_at: 15.minutes.ago)
    expect { post update_status_path(item), params: { expires_at: '13:00' } }.not_to change(Status, :count)
    expect(status.reload.user).to eq(user)
  end

  it 'rejects extending or ending another user’s usage' do
    status = reserve(owner: other_user)
    post extend_status_path(item), params: { expires_at: '13:00' }
    expect(status.reload.expires_at).to eq(30.minutes.from_now)
    post end_use_status_path(item)
    expect(status.reload.use_flg).to be(true)
    expect(flash[:notice]).to include('自分が使用中ではありません')
  end

  it 'rejects extending to an equal or earlier deadline' do
    status = reserve
    %w[12:30 12:00].each do |deadline|
      post extend_status_path(item), params: { expires_at: deadline }
      expect(status.reload.expires_at).to eq(30.minutes.from_now)
      expect(flash[:notice]).to eq('使用期限以前の時刻は指定できません。')
    end
  end

  it 'handles ending or extending an unused item' do
    post end_use_status_path(item)
    expect(response).to redirect_to(status_path)
    expect(flash[:notice]).to include('使用中ではありません')
    post extend_status_path(item), params: { expires_at: '13:00' }
    expect(response).to redirect_to(status_path)
    status = reserve(use_flg: false)
    post extend_status_path(item), params: { expires_at: '13:00' }
    expect(status.reload.use_flg).to be(false)
  end

  it 'renders the usage page with the refresh marker' do
    reserve
    get status_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-auto-refresh', '自分が', '延長する', '使用終了')
  end

  [nil, '', ' '].each do |webhook_url|
    it "skips Slack notifications when the webhook URL is #{webhook_url.inspect}" do
      allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(webhook_url)
      post update_status_path(item), params: { expires_at: '12:30' }
      expect(response).to redirect_to(status_path)
      expect(item.reload.status.use_flg).to be(true)
      expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
    end
  end

  context 'with Slack configured' do
    let(:webhook_url) { 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET' }

    before do
      allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(webhook_url)
    end

    it 'posts notifications for starting, extending and ending usage' do
      texts = [
        "#{item.name}を[#{I18n.l Time.zone.local(2026, 10, 27, 12, 30), format: :short}]迄 #{user.name}さんが使用します。",
        "#{item.name}を[#{I18n.l Time.zone.local(2026, 10, 27, 13), format: :short}]迄 #{user.name}さんが使用延長しました。",
        "#{item.name}を#{user.name}さんが使用終了しました。"
      ]
      notifications = texts.map do |text|
        stub_request(:post, webhook_url)
          .with(headers: { 'Content-Type' => 'application/json' }, body: { text: text }.to_json)
          .to_return(status: 200, body: 'ok')
      end
      post update_status_path(item), params: { expires_at: '12:30' }
      post extend_status_path(item), params: { expires_at: '13:00' }
      post end_use_status_path(item)
      notifications.each { |notification| expect(notification).to have_been_requested.once }
    end

    it 'keeps the successful reservation when Slack times out' do
      stub_request(:post, webhook_url).to_timeout
      expect(Rails.logger).to receive(:warn).with('Slack notification failed (Net::OpenTimeout)')
      post update_status_path(item), params: { expires_at: '12:30' }
      expect(response).to redirect_to(status_path)
      expect(item.reload.status.use_flg).to be(true)
    end

    it 'keeps the successful reservation when Slack returns an error' do
      stub_request(:post, webhook_url).to_return(status: 403, body: 'action_prohibited')
      expect(Rails.logger).to receive(:warn).with('Slack notification failed (HTTP 403)')
      post update_status_path(item), params: { expires_at: '12:30' }
      expect(response).to redirect_to(status_path)
      expect(item.reload.status.use_flg).to be(true)
    end

    ['not a URL', 'http://hooks.slack.com/services/TEST/CHANNEL/SECRET', 'https:/missing-host'].each do |invalid_url|
      context "with invalid webhook URL #{invalid_url.inspect}" do
        let(:webhook_url) { invalid_url }

        it 'keeps the successful reservation and logs no webhook URL' do
          expect(Rails.logger).to receive(:warn).with(/\ASlack notification failed \((invalid webhook URL|URI::InvalidURIError)\)\z/)
          post update_status_path(item), params: { expires_at: '12:30' }
          expect(response).to redirect_to(status_path)
          expect(item.reload.status.use_flg).to be(true)
          expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
        end
      end
    end
  end
end
