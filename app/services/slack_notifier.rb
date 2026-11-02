require 'net/https'

class SlackNotifier
  MAX_ATTEMPTS = 2
  NETWORK_ERRORS = [Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError,
                    EOFError, Net::HTTPBadResponse, Net::ProtocolError].freeze

  # Return false only for a failed delivery; an unconfigured webhook is intentional.
  def self.deliver(payload)
    webhook_url = ENV['SLACK_WEBHOOK_URL']
    if webhook_url.blank?
      Rails.logger.debug { "Slack通知スキップ(Webhook未設定): #{payload[:text]}" }
      return :skipped
    end

    uri = URI.parse(webhook_url)
    unless uri.is_a?(URI::HTTPS) && uri.host.present?
      Rails.logger.warn 'Slack notification failed (invalid webhook URL)'
      return false
    end

    MAX_ATTEMPTS.times do |attempt|
      begin
        response = post(uri, payload)
        return true if response.is_a?(Net::HTTPSuccess)

        # Do not repeat permanent errors or hammer a rate-limited webhook.
        next if response.code.to_i >= 500 && attempt + 1 < MAX_ATTEMPTS

        Rails.logger.warn "Slack notification failed (HTTP #{response.code})"
        return false
      rescue *NETWORK_ERRORS => e
        next if attempt + 1 < MAX_ATTEMPTS

        Rails.logger.warn "Slack notification failed (#{e.class})"
        return false
      end
    end
  rescue URI::InvalidURIError => e
    Rails.logger.warn "Slack notification failed (#{e.class})"
    false
  end

  def self.post(uri, payload)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    # Retry counts are owned by deliver, including Net::HTTP's default retries.
    http.max_retries = 0
    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/json'
    req.body = payload.to_json
    http.request(req)
  end

  private_class_method :post
end
