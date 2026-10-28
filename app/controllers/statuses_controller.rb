require 'net/https'

class StatusesController < ApplicationController
  def home
    @items = Item.all
  end

  def update_status
    if params[:expires_at].blank?
      redirect_to status_path, notice: '期限を指定してください。'
      return
    end

    item = Item.find(params[:id])
    item.with_lock do
      if item.status.blank?
        item.build_status
      elsif item.status.use?(current_user.id) || item.status.grace_period?
        redirect_to status_path, notice: "#{item.name}は既に使用中です。"
        return
      end

      item.status.set(current_user.id, params[:expires_at].in_time_zone)
    end
    post_slack("#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 #{current_user.name}さんが使用します。")
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 使用します。"
  end

  def extend_status
    if params[:expires_at].blank?
      redirect_to status_path, notice: '期限を指定してください。'
      return
    end

    item = Item.find(params[:id])
    item.with_lock do
      if item.status.blank? || !item.status.use_flg?
        redirect_to status_path, notice: "#{item.name}は使用中ではありません。"
        return
      elsif item.status.user_id != current_user.id
        redirect_to status_path, notice: "#{item.name}は自分が使用中ではありません。"
        return
      elsif params[:expires_at].in_time_zone <= item.status.expires_at
        redirect_to status_path, notice: '使用期限以前の時刻は指定できません。'
        return
      end

      item.status.set(current_user.id, params[:expires_at].in_time_zone)
    end
    post_slack("#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 #{current_user.name}さんが使用延長しました。")
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 使用延長します。"
  end

  def end_use_status
    item = Item.find(params[:id])
    item.with_lock do
      status = item.status
      if status.nil? || !status.use_flg?
        redirect_to status_path, notice: "#{item.name}は使用中ではありません。"
        return
      elsif status.user_id != current_user.id
        redirect_to status_path, notice: "#{item.name}は自分が使用中ではありません。"
        return
      end
      status.reset
    end
    post_slack("#{item.name}を#{current_user.name}さんが使用終了しました。")
    redirect_to status_path, notice: "#{item.name}を使用終了しました。"
  end

  private

  def post_slack(text)
    post_text = text.to_s
    webhook_url = ENV['SLACK_WEBHOOK_URL']
    if webhook_url.blank? || post_text.blank?
      logger.debug post_text
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
    req.body = { text: post_text }.to_json
    response = http.request(req)
    logger.warn "Slack notification failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
  rescue URI::InvalidURIError, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
    logger.warn "Slack notification failed (#{e.class})"
  end
end
