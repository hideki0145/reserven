class ReservationsController < ApplicationController
  before_action :load_reservation, only: [:edit, :update]
  rescue_from ReservationBooking::Forbidden, with: :forbidden

  def index
    @checked_at = Time.current
    @filters = params.permit(:target, :member).to_h
    rows = Usage.reservations.outstanding(@checked_at)
    rows = rows.where(item_id: @filters['target']) if @filters['target'].present?
    if @filters['member'].present?
      rows = rows.where(user_id: @filters['member'] == 'self' ? current_user.id : @filters['member'])
    end
    @pages = [(rows.count / 25.0).ceil, 1].max
    value = params[:page].is_a?(String) ? Integer(params[:page], exception: false) : nil
    @page = [[value || 1, 1].max, @pages].min
    @usages = rows.order(:starts_at, :id).includes(:item, :user).limit(25).offset((@page - 1) * 25)
    @targets = Item.where(usage_mode: 'reservation').in_order
    @members = User.in_order
  end

  def new
    @input = { 'timing' => params[:timing] == 'now' ? 'now' : 'future',
               'starts_at' => (15.minutes.from_now).strftime('%Y-%m-%dT%H:%M'),
               'ends_at' => (45.minutes.from_now).strftime('%Y-%m-%dT%H:%M'),
               'item_ids' => params.permit(item_ids: [])[:item_ids] || [] }
    prepare_form
  end

  def create
    @input = booking_params.to_h
    immediate = @input['timing'] == 'now'
    raise ReservationBooking::Invalid, '利用開始の指定が正しくありません。' unless ['now', 'future'].include?(@input['timing'])

    usages = ReservationBooking.create!(actor: current_user, item_ids: @input['item_ids'],
                                       user_id: @input['user_id'].presence, reason: @input['reason'],
                                       starts_at: immediate ? nil : parse_time(@input['starts_at']),
                                       ends_at: parse_time(@input['ends_at']), immediate: immediate)
    SlackNotifier.deliver(ReservationNotification.build(event: immediate ? :start : :create, usages: usages, actor: current_user))
    redirect_to immediate ? status_path : reservations_path, notice: "#{usages.length}件の予約を登録しました。"
  rescue ReservationBooking::Invalid, ActiveRecord::RecordInvalid => e
    invalid_form(e, :new)
  end

  def edit
    if @usage.item.nil? || @usage.item.disabled? || @usage.user.nil? || @usage.user.disabled?
      redirect_to reservation_return_path, alert: '無効な対象・利用者の予約は、取消または利用終了してください。'
      return
    end
    unless [:scheduled, :active].include?(@usage.reservation_state)
      redirect_to reservation_return_path, alert: '終了・取消済みの予約は変更できません。'
      return
    end
    @input = { 'starts_at' => @usage.starts_at.strftime('%Y-%m-%dT%H:%M'),
               'ends_at' => @usage.ends_at.strftime('%Y-%m-%dT%H:%M'), 'reason' => @usage.reason }
    prepare_form
  end

  def update
    @input = booking_params.to_h
    start = @input['starts_at'] == @usage.starts_at.iso8601(6) ? @usage.starts_at : parse_time(@input['starts_at'])
    result = ReservationBooking.update!(@usage.id, actor: current_user, starts_at: start,
                                         ends_at: parse_time(@input['ends_at']), reason: @input['reason'])
    SlackNotifier.deliver(ReservationNotification.build(event: :update, usages: [result.usage], actor: current_user, previous: result.previous))
    redirect_to reservation_return_path, notice: '予約を更新しました。'
  rescue ReservationBooking::Invalid, ActiveRecord::RecordInvalid => e
    invalid_form(e, :edit)
  end

  def cancel
    usage = ReservationBooking.cancel!(params[:id], actor: current_user)
    SlackNotifier.deliver(ReservationNotification.build(event: :cancel, usages: [usage], actor: current_user))
    redirect_to reservations_path, notice: '予約を取り消しました。'
  rescue ReservationBooking::Invalid => e
    redirect_to reservation_return_path, alert: e.message
  end

  def finish
    usage = ReservationBooking.finish!(params[:id], actor: current_user)
    SlackNotifier.deliver(ReservationNotification.build(event: :finish, usages: [usage], actor: current_user))
    redirect_to reservation_return_path, notice: '利用終了しました。残りの期間は予約できます。'
  rescue ReservationBooking::Invalid => e
    redirect_to reservation_return_path, alert: e.message
  end

  private

  def reservation_return_path
    params[:return_to] == 'status' ? status_path : reservations_path
  end
  helper_method :reservation_return_path

  def booking_params
    params.require(:reservation).permit(:timing, :starts_at, :ends_at, :user_id, :reason, item_ids: [])
  end

  def parse_time(value)
    unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)
      raise ReservationBooking::Invalid, '開始・終了日時を正しく入力してください。'
    end
    year, month, day, hour, minute = value.scan(/\d+/).map(&:to_i)
    unless Date.valid_date?(year, month, day) && hour < 24 && minute < 60
      raise ReservationBooking::Invalid, '存在する日時を入力してください。'
    end
    Time.zone.local(year, month, day, hour, minute)
  end

  def load_reservation
    @usage = Usage.reservations.find(params[:id])
    unless @usage.user_id == current_user.id || current_user.usage_manager?
      raise ReservationBooking::Forbidden, '他の利用者の予約を操作する権限がありません。'
    end
  end

  def prepare_form
    if !@usage && @input['timing'] == 'now' && @input['starts_at'].blank?
      @input['starts_at'] = (15.minutes.from_now).strftime('%Y-%m-%dT%H:%M')
    end
    @targets = Item.where(usage_mode: 'reservation', disabled: false).in_order
    @members = User.where(disabled: false).in_order
    @selected_ids = Array(@input['item_ids']).map(&:to_s)
    @active = @usage && @usage.starts_at <= Time.current
    @reason_policy = @usage&.reason_policy_snapshot
  end

  def invalid_form(error, template)
    @error = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(' ') : error.message
    prepare_form
    render template, status: :unprocessable_content
  end

  def forbidden(error)
    render plain: error.message, status: :forbidden
  end
end
