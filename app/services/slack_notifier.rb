require 'net/https'

class SlackNotifier
  def self.deliver(payload)
    webhook_url = ENV['SLACK_WEBHOOK_URL']
    if webhook_url.blank?
      Rails.logger.debug { "Slack通知スキップ(Webhook未設定): #{payload[:text]}" }
      return
    end

    uri = URI.parse(webhook_url)
    unless uri.is_a?(URI::HTTPS) && uri.host.present?
      Rails.logger.warn 'Slack notification failed (invalid webhook URL)'
      return
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/json'
    req.body = payload.to_json
    response = http.request(req)
    Rails.logger.warn "Slack notification failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
  rescue URI::InvalidURIError, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
    Rails.logger.warn "Slack notification failed (#{e.class})"
  end
end
