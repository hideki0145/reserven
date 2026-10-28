require 'net/https'

class StatusesController < ApplicationController
  def home
    @items = Item.all
  end

  def deadline_preview
    expires_at = UsageDeadline.parse(params[:expires_at])
    render json: {
      confirmation_required: expires_at.to_date != Time.current.to_date,
      expires_at: expires_at.iso8601,
      label: "#{expires_at.to_date == Time.current.to_date.tomorrow ? '翌日 ' : ''}#{I18n.l(expires_at, format: '%m/%d(%a) %H:%M')}"
    }
  rescue UsageDeadline::Invalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def update_status
    item = Item.find(params[:id])
    item.with_lock do
      if item.status.blank?
        item.build_status
      elsif item.status.use?(current_user.id) || item.status.grace_period?
        redirect_to status_path, notice: "#{item.name}は既に利用中です。"
        return
      end

      expires_at = UsageDeadline.parse(params[:expires_at])
      return if confirm_overnight_usage(item, expires_at, :start)

      item.status.set(current_user.id, expires_at)
    end
    post_slack(SlackUsageNotification.build(event: :start, item: item, user: current_user, expires_at: item.status.expires_at))
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 利用します。"
  rescue UsageDeadline::Invalid => e
    redirect_to status_path, alert: e.message
  end

  def extend_status
    item = Item.find(params[:id])
    previous_expires_at = nil
    item.with_lock do
      if item.status.blank? || !item.status.use_flg?
        redirect_to status_path, notice: "#{item.name}は利用中ではありません。"
        return
      elsif item.status.user_id != current_user.id
        redirect_to status_path, notice: "#{item.name}は自分が利用中ではありません。"
        return
      end

      expires_at = UsageDeadline.parse(params[:expires_at])
      if expires_at <= item.status.expires_at
        redirect_to status_path, alert: '利用期限以前の時刻は指定できません。'
        return
      end

      return if confirm_overnight_usage(item, expires_at, :extend)

      previous_expires_at = item.status.expires_at
      item.status.set(current_user.id, expires_at)
    end
    post_slack(SlackUsageNotification.build(event: :extend, item: item, user: current_user,
                                          expires_at: item.status.expires_at, previous_expires_at: previous_expires_at))
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 利用延長します。"
  rescue UsageDeadline::Invalid => e
    redirect_to status_path, alert: e.message
  end

  def end_use_status
    item = Item.find(params[:id])
    item.with_lock do
      status = item.status
      if status.nil? || !status.use_flg?
        redirect_to status_path, notice: "#{item.name}は利用中ではありません。"
        return
      elsif status.user_id != current_user.id
        redirect_to status_path, notice: "#{item.name}は自分が利用中ではありません。"
        return
      end
      status.reset
    end
    post_slack(SlackUsageNotification.build(event: :end, item: item, user: current_user))
    redirect_to status_path, notice: "#{item.name}を利用終了しました。"
  end

  private

  def confirm_overnight_usage(item, expires_at, operation)
    return false if expires_at.to_date == Time.current.to_date
    return false if params[:confirmed_expires_at] == expires_at.iso8601

    @item = item
    @expires_at = expires_at
    @operation = operation
    render :confirm_deadline
    true
  end

  def post_slack(payload)
    webhook_url = ENV['SLACK_WEBHOOK_URL']
    if webhook_url.blank?
      logger.debug { "Slack通知スキップ(Webhook未設定): #{payload[:text]}" }
      return
    end

    uri = URI.parse(webhook_url)
    unless uri.is_a?(URI::HTTPS) && uri.host.present?
      logger.warn 'Slack notification failed (invalid webhook URL)'
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
    logger.warn "Slack notification failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
  rescue URI::InvalidURIError, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
    logger.warn "Slack notification failed (#{e.class})"
  end
end
