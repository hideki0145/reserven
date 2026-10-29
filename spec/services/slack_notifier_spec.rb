require 'rails_helper'

RSpec.describe SlackNotifier do
  let(:webhook_url) { 'https://hooks.slack.com/services/TEST/CHANNEL/SECRET?test=1' }
  let(:payload) { { text: '利用通知', blocks: [{ type: 'section', text: { type: 'plain_text', text: '利用通知' } }] } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(webhook_url)
  end

  it 'posts the complete payload as JSON without logging a successful delivery' do
    notification = stub_request(:post, webhook_url)
      .with(headers: { 'Content-Type' => 'application/json' }, body: payload.to_json)
      .to_return(status: 200, body: 'ok')
    expect(Rails.logger).not_to receive(:warn)
    expect(Rails.logger).not_to receive(:debug)

    described_class.deliver(payload)

    expect(notification).to have_been_requested.once
  end

  [nil, '', ' '].each do |value|
    context "when the webhook URL is #{value.inspect}" do
      let(:webhook_url) { value }

      it 'skips communication and logs the reason and summary at debug level' do
        messages = []
        allow(Rails.logger).to receive(:debug) do |*args, &message|
          messages << (message ? message.call : args.first)
        end
        described_class.deliver(payload)
        expect(messages).to eq(['Slack通知スキップ(Webhook未設定): 利用通知'])
        expect(WebMock).not_to have_requested(:any, /.*/)
      end
    end
  end

  ['not a URL', 'http://hooks.slack.com/services/TEST/CHANNEL/SECRET', 'https:/missing-host'].each do |value|
    context "when the webhook URL is invalid: #{value.inspect}" do
      let(:webhook_url) { value }

      it 'skips communication and logs a warning without the URL' do
        expect(Rails.logger).to receive(:warn).with(/\ASlack notification failed \((invalid webhook URL|URI::InvalidURIError)\)\z/)
        described_class.deliver(payload)
        expect(WebMock).not_to have_requested(:any, /.*/)
      end
    end
  end

  [403, 500].each do |status|
    it "logs HTTP #{status} without exposing the URL or response body" do
      notification = stub_request(:post, webhook_url).to_return(status: status, body: 'SECRET')
      expect(Rails.logger).to receive(:warn).with("Slack notification failed (HTTP #{status})")
      described_class.deliver(payload)
      expect(notification).to have_been_requested.once
    end
  end

  [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED,
   Errno::ECONNRESET, OpenSSL::SSL::SSLError, EOFError].each do |error_class|
    it "absorbs #{error_class} and logs only its class" do
      notification = stub_request(:post, webhook_url).to_raise(error_class.new('SECRET'))
      expect(Rails.logger).to receive(:warn).with("Slack notification failed (#{error_class})")
      expect { described_class.deliver(payload) }.not_to raise_error
      expect(notification).to have_been_requested.once
    end
  end
end
