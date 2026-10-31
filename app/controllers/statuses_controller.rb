class StatusesController < ApplicationController
  def home
    @items = Item.where(usage_mode: 'immediate').visible_on_status.in_order.includes(current_usage: :user)
    @reservation_checked_at = Time.current
    reservable = Item.where(usage_mode: 'reservation')
    @reservation_items = reservable.where(disabled: false)
                                    .or(reservable.where(id: Usage.reservations.outstanding(@reservation_checked_at).select(:item_id))).in_order
    ids = @reservation_items.select(:id)
    current = Usage.reservations.outstanding(@reservation_checked_at).where(item_id: ids).where('starts_at <= ?', @reservation_checked_at).includes(:user)
    following = Usage.next_reservations(ids, now: @reservation_checked_at)
    @reservation_rows = (current.to_a + following.to_a).sort_by { |usage| [usage.starts_at, usage.id] }.group_by(&:item_id)
  end

  def deadline_preview
    expires_at = UsageDeadline.parse(params[:expires_at])
    render json: {
      confirmation_required: expires_at.to_date != Time.current.to_date,
      expires_at: expires_at.iso8601,
      label: "#{expires_at.to_date == Time.current.to_date.tomorrow ? '翌日 ' : ''}#{I18n.l(expires_at, format: :usage_deadline)}"
    }
  rescue UsageDeadline::Invalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def update_status
    item = Item.find(params[:id])
    usage = nil
    item.with_lock do
      return if reject_inactive_actor
      return if reject_disabled_item(item)

      unless item.can_start_usage?(current_user.id)
        redirect_to status_path, notice: "#{item.name}は既に利用中です。"
        return
      end

      expires_at = UsageDeadline.parse(params[:expires_at])
      return if confirm_overnight_usage(item, expires_at, :start)

      usage = item.start_usage!(current_user, expires_at, reason: params.permit(:reason)[:reason])
    end
    SlackNotifier.deliver(SlackUsageNotification.build(event: :start, item: item, user: current_user, expires_at: usage.ends_at, reason: usage.reason))
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l usage.ends_at, format: :usage_deadline}]迄 利用します。"
  rescue UsageDeadline::Invalid => e
    redirect_to status_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.is_a?(Usage)

    home
    @failed_item_id = item.id
    @reason_input = params.permit(:reason)[:reason]
    flash.now[:alert] = e.record.errors.full_messages.join(' ')
    render :home, status: :unprocessable_content
  end

  def extend_status
    item = Item.find(params[:id])
    previous_expires_at = nil
    usage = nil
    item.with_lock do
      return if reject_inactive_actor
      return if reject_disabled_item(item)

      if item.current_usage.nil?
        redirect_to status_path, notice: "#{item.name}は利用中ではありません。"
        return
      elsif !item.can_extend_usage?(current_user.id, manager: current_user.usage_manager?)
        redirect_to status_path, notice: "#{item.name}は自分が利用中ではありません。"
        return
      end
      return if reject_changed_usage(item.current_usage)

      expires_at = UsageDeadline.parse(params[:expires_at])
      if expires_at <= item.current_usage.ends_at
        redirect_to status_path, alert: '利用期限以前の時刻は指定できません。'
        return
      end

      return if confirm_overnight_usage(item, expires_at, :extend)

      previous_expires_at = item.current_usage.ends_at
      usage = item.current_usage
      usage.extend!(expires_at, current_user)
    end
    SlackNotifier.deliver(SlackUsageNotification.build(event: :extend, item: item, user: usage.user, actor: current_user,
                                                     expires_at: usage.ends_at, previous_expires_at: previous_expires_at, reason: usage.reason))
    redirect_to status_path, notice: "#{item.name}を[#{I18n.l usage.ends_at, format: :usage_deadline}]迄 利用延長します。"
  rescue UsageDeadline::Invalid => e
    redirect_to status_path, alert: e.message
  end

  def end_use_status
    item = Item.find(params[:id])
    usage = nil
    item.with_lock do
      return if reject_inactive_actor
      usage = item.current_usage
      if usage.nil?
        redirect_to status_path, notice: "#{item.name}は利用中ではありません。"
        return
      elsif !item.can_end_usage?(current_user.id, manager: current_user.usage_manager?)
        redirect_to status_path, notice: "#{item.name}は自分が利用中ではありません。"
        return
      end
      return if reject_changed_usage(usage)
      usage.finish!(current_user)
    end
    SlackNotifier.deliver(SlackUsageNotification.build(event: :end, item: item, user: usage.user, actor: current_user, reason: usage.reason))
    redirect_to status_path, notice: "#{item.name}を利用終了しました。"
  end

  private

  def reject_changed_usage(usage)
    expected = params[:usage_id]
    return false if expected.blank? && usage.user_id == current_user.id
    return false if expected.to_s == usage.id.to_s

    redirect_to status_path, alert: '利用状況が変わった可能性があります。最新の内容を確認して操作し直してください。'
    true
  end

  def reject_inactive_actor
    return false unless current_user.reload.disabled?

    reset_session
    cookies.delete(:user_id)
    cookies.delete(:remember_token)
    @current_user = nil
    redirect_to login_path
    true
  end

  def reject_disabled_item(item)
    return false unless item.disabled?

    redirect_to status_path, alert: "#{item.name}は利用停止中です。"
    true
  end

  def confirm_overnight_usage(item, expires_at, operation)
    return false if expires_at.to_date == Time.current.to_date
    return false if params[:confirmed_expires_at] == expires_at.iso8601

    @item = item
    @expires_at = expires_at
    @operation = operation
    render :confirm_deadline
    true
  end
end
