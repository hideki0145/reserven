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
    if item.status.blank?
      item.build_status
    elsif item.status.use?(current_user.id)
      redirect_to status_path, notice: "#{item.name}は既に使用中です。"
      return
    end

    item.status.set(current_user.id, params[:expires_at].in_time_zone)
    post_slack("#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 #{current_user.name}さんが使用します。")
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 使用します。"
  end

  def extend_status
    if params[:expires_at].blank?
      redirect_to status_path, notice: '期限を指定してください。'
      return
    end

    item = Item.find(params[:id])
    if item.status.blank?
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
    post_slack("#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 #{current_user.name}さんが使用延長しました。")
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l item.status.expires_at, format: :short}]迄 使用延長します。"
  end

  def end_use_status
    item = Item.find(params[:id])
    status = item.status
    if status.user_id != current_user.id
      redirect_to status_path, notice: "#{item.name}は自分が使用中ではありません。"
      return
    end
    status.reset
    post_slack("#{item.name}を#{current_user.name}さんが使用終了しました。")
    redirect_to status_path, notice: "#{item.name}を使用終了しました。"
  end

  private

  def post_slack(text)
    post_text = text.to_s
    if ENV['SLACK_TOKEN'].blank? || ENV['SLACK_CHANNEL'].blank? || post_text.blank?
      logger.debug post_text
      return
    end

    uri = URI.parse('https://slack.com/api/chat.postMessage')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Post.new(uri.path)
    req.set_form_data(
      token: ENV['SLACK_TOKEN'],
      channel: ENV['SLACK_CHANNEL'],
      text: post_text
    )
    logger.info http.request(req)
  end
end
