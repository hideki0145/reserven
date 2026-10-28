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

  it 'previews an overnight deadline without writing or sending notifications' do
    expect do
      post deadline_preview_path, params: { expires_at: '00:10' }
    end.not_to change(Status, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('confirmation_required' => true, 'label' => '翌日 10/28(水) 00:10')
    post deadline_preview_path, params: { expires_at: 'invalid' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
  end

  it 'rejects an empty deadline' do
    expect { post update_status_path(item), params: { expires_at: '' } }.not_to change(Status, :count)
    expect(flash[:alert]).to eq('期限を指定してください。')
  end

  it 'requires confirmation before starting usage tomorrow, then saves and notifies once' do
    travel_to(Time.zone.local(2026, 10, 27, 23, 55))
    deadline = Time.zone.local(2026, 10, 28, 0, 10)
    webhook_url = 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET'
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(webhook_url)
    notification = stub_request(:post, webhook_url).to_return(status: 200, body: 'ok')

    expect { post update_status_path(item), params: { expires_at: '00:10' } }.not_to change(Status, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('日付をまたぐ利用の確認', '翌日 10/28(水) 00:10')
    expect(notification).not_to have_been_requested

    post update_status_path(item), params: { expires_at: '00:10', confirmed_expires_at: deadline.iso8601 }
    expect(item.reload.status.expires_at).to eq(deadline)
    expect(notification).to have_been_requested.once
  end

  it 'does not extend usage until an overnight deadline is confirmed' do
    travel_to(Time.zone.local(2026, 10, 27, 23, 30))
    status = reserve(expires_at: Time.zone.local(2026, 10, 27, 23, 55))
    post extend_status_path(item), params: { expires_at: '00:10' }
    expect(response.body).to include('日付をまたぐ利用の確認')
    expect(status.reload.expires_at).to eq(Time.zone.local(2026, 10, 27, 23, 55))
    deadline = Time.zone.local(2026, 10, 28, 0, 10)
    post extend_status_path(item), params: { expires_at: '00:10', confirmed_expires_at: deadline.iso8601 }
    expect(status.reload.expires_at).to eq(deadline)
  end

  it 'rechecks availability after a confirmation page was displayed' do
    travel_to(Time.zone.local(2026, 10, 27, 23, 55))
    post update_status_path(item), params: { expires_at: '00:10' }
    status = reserve(owner: other_user, expires_at: 30.minutes.from_now)
    post update_status_path(item), params: { expires_at: '00:10', confirmed_expires_at: Time.zone.local(2026, 10, 28, 0, 10).iso8601 }
    expect(response).to redirect_to(status_path)
    expect(status.reload.user).to eq(other_user)
  end

  it 'asks for confirmation again if the deadline changed while the page was open' do
    travel_to(Time.zone.local(2026, 10, 27, 23, 55))
    old_deadline = Time.zone.local(2026, 10, 28, 0, 10)
    post update_status_path(item), params: { expires_at: '00:10' }
    travel_to(Time.zone.local(2026, 10, 28, 0, 20))
    expect do
      post update_status_path(item), params: { expires_at: '00:10', confirmed_expires_at: old_deadline.iso8601 }
    end.not_to change(Status, :count)
    expect(response.body).to include('翌日 10/29(木) 00:10')
  end

  it 'rejects malformed and explicit past deadlines without creating usage or notifying Slack' do
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return('https://hooks.slack.com/services/TEST/CHANNEL/SECRET')
    ['invalid', '24:00', '12:00', '2026-10-27T11:00', '2026-10-27T12:00'].each do |deadline|
      expect { post update_status_path(item), params: { expires_at: deadline } }.not_to change(Status, :count)
      expect(response).to redirect_to(status_path)
      expect(flash[:alert]).to be_present
    end
    expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
  end

  it 'preserves existing usage when an extension is invalid or already past' do
    status = reserve(expires_at: 30.minutes.ago)
    ['invalid', '2026-10-27T11:45', '2026-10-27T12:00'].each do |deadline|
      post extend_status_path(item), params: { expires_at: deadline }
      expect(response).to redirect_to(status_path)
      expect(status.reload.expires_at).to eq(30.minutes.ago)
      expect(flash[:alert]).to be_present
    end
  end

  it 'provides time-only input and defaults an extension after the existing deadline' do
    reserve(expires_at: Time.zone.local(2026, 10, 27, 23, 55))
    get status_path
    input = Nokogiri::HTML(response.body).at_css('input[name="expires_at"]')
    expect(input['type']).to eq('time')
    expect(input['value']).to eq('00:10')
    expect(response.body).to include('翌日')
    expect(response.body).not_to include('日本時間')
  end

  it 'defaults expired usage extensions to fifteen minutes from now' do
    reserve(expires_at: 5.minutes.ago)
    get status_path
    expect(Nokogiri::HTML(response.body).at_css('input[name="expires_at"]')['value']).to eq('12:15')
  end

  it 'rejects taking an item already in use by another user' do
    status = reserve(owner: other_user)
    post update_status_path(item), params: { expires_at: '13:00' }
    expect(status.reload.user).to eq(other_user)
    expect(flash[:notice]).to include('既に利用中')
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
    expect(flash[:notice]).to include('自分が利用中ではありません')
  end

  it 'rejects extending to an equal or earlier deadline' do
    status = reserve
    ['2026-10-27T12:30', '2026-10-27T12:15'].each do |deadline|
      post extend_status_path(item), params: { expires_at: deadline }
      expect(status.reload.expires_at).to eq(30.minutes.from_now)
      expect(flash[:alert]).to eq('利用期限以前の時刻は指定できません。')
    end
  end

  it 'handles ending or extending an unused item' do
    post end_use_status_path(item)
    expect(response).to redirect_to(status_path)
    expect(flash[:notice]).to include('利用中ではありません')
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
    expect(response.body).to include('data-auto-refresh', '🔵 利用中', '(自分)', '10/27(火) 12:30', '延長する', '利用終了')
  end

  it 'shows availability without stale usage details after usage ends' do
    reserve(use_flg: false)
    get status_path
    expect(response.body).to include('✅ 利用可能', '利用する')
    expect(response.body).not_to include('利用期限:', '延長する', '利用終了')
  end

  [true, false].each do |own_usage|
    it "shows the grace period and preserves actions for own_usage=#{own_usage}" do
      reserve(owner: own_usage ? user : other_user, expires_at: 5.minutes.ago)
      get status_path
      expect(response.body).to include('🟠 猶予期間中', '期限後15分', '10/27(火) 11:55')
      if own_usage
        expect(response.body).to include('延長する', '利用終了')
      else
        expect(response.body).not_to include('延長する', '利用終了', 'value="利用する"')
      end
    end
  end

  it 'shows availability after another user’s grace period ends' do
    reserve(owner: other_user, expires_at: 15.minutes.ago)
    get status_path
    expect(response.body).to include('✅ 利用可能', '利用する')
    expect(response.body).not_to include('猶予期間中', '利用期限:')
  end

  [nil, '', ' '].each do |webhook_url|
    it "skips Slack notifications when the webhook URL is #{webhook_url.inspect}" do
      allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(webhook_url)
      debug_messages = []
      allow(Rails.logger).to receive(:debug) do |*args, &message|
        debug_messages << (message ? message.call : args.first)
      end
      post update_status_path(item), params: { expires_at: '12:30' }
      expect(response).to redirect_to(status_path)
      expect(item.reload.status.use_flg).to be(true)
      expect(debug_messages).to include(
        "Slack通知スキップ(Webhook未設定): #{item.name}を#{user.name}さんが10/27(火) 12:30まで利用します。"
      )
      expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
    end
  end

  context 'with Slack configured' do
    let(:webhook_url) { 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET' }

    before do
      allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(webhook_url)
    end

    it 'posts notifications for starting, extending and ending usage' do
      expected = [
        ["🔵 *#{item.name} の利用を開始*", '利用期限', '10/27(火) 12:30',
         "#{item.name}を#{user.name}さんが10/27(火) 12:30まで利用します。"],
        ["🕒 *#{item.name} の利用を延長*", '利用期限', '10/27(火) 12:30 → 13:00',
         "#{item.name}の利用期限を#{user.name}さんが10/27(火) 12:30 → 13:00に延長しました。"],
        ["✅ *#{item.name} の利用を終了*", '状態', '利用可能',
         "#{item.name}を#{user.name}さんが利用終了しました。現在は利用可能です。"]
      ]
      notifications = expected.map do |title, label, value, text|
        stub_request(:post, webhook_url)
          .with(headers: { 'Content-Type' => 'application/json' }) do |request|
            payload = JSON.parse(request.body)
            payload['text'] == text && payload['blocks'] == [
              { 'type' => 'section', 'text' => { 'type' => 'mrkdwn', 'text' => title, 'verbatim' => true } },
              { 'type' => 'section', 'text' => {
                'type' => 'mrkdwn', 'verbatim' => true,
                'text' => title.include?('利用を延長') ? "*利用者*: #{user.name}\n*変更前*: 10/27(火) 12:30\n*利用期限*: 10/27(火) 13:00" : "*利用者*: #{user.name}\n*#{label}*: #{value}"
              } }
            ]
          end
          .to_return(status: 200, body: 'ok')
      end
      post update_status_path(item), params: { expires_at: '12:30' }
      post extend_status_path(item), params: { expires_at: '13:00' }
      post end_use_status_path(item)
      notifications.each { |notification| expect(notification).to have_been_requested.once }
    end

    it 'shows both dates when an extension crosses midnight' do
      reserve(expires_at: Time.zone.local(2026, 10, 27, 23, 30))
      notification = stub_request(:post, webhook_url).with do |request|
        payload = JSON.parse(request.body)
        payload['blocks'][1]['text']['text'] == "*利用者*: #{user.name}\n*変更前*: 10/27(火) 23:30\n*利用期限*: 10/28(水) 00:30"
      end.to_return(status: 200, body: 'ok')
      post extend_status_path(item), params: { expires_at: '2026-10-28 00:30', confirmed_expires_at: Time.zone.local(2026, 10, 28, 0, 30).iso8601 }
      expect(notification).to have_been_requested.once
    end

    it 'escapes Slack control characters in item and user names' do
      item.update!(name: 'PC & <!channel>')
      user.update!(name: '<管理者> & Co.')
      notification = stub_request(:post, webhook_url).with do |request|
        blocks = JSON.parse(request.body)['blocks']
        blocks[0]['text']['text'] == '🔵 *PC &amp; &lt;!channel&gt; の利用を開始*' &&
          blocks[1]['text']['text'] == "*利用者*: &lt;管理者&gt; &amp; Co.\n*利用期限*: 10/27(火) 12:30"
      end.to_return(status: 200, body: 'ok')
      post update_status_path(item), params: { expires_at: '12:30' }
      expect(notification).to have_been_requested.once
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
