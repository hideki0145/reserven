class ReservationBooking
  class Invalid < StandardError; end
  class Forbidden < StandardError; end
  Change = Struct.new(:usage, :previous, keyword_init: true)
  KEEP_REASON = Object.new.freeze

  # SQLite serializes the write transaction; every operation locks items in ID order.
  # Notifications belong to the caller and are sent only after this transaction commits.
  def self.create!(actor:, item_ids:, ends_at:, starts_at: nil, user_id: nil, reason: nil, immediate: false)
    ids = normalize_ids(item_ids)
    Item.transaction do
      authorize_actor!(actor)
      owner = User.find_by(id: user_id || actor.id)
      raise Invalid, '有効な利用者を選択してください。' unless owner && !owner.disabled?
      raise Forbidden, '代理登録する権限がありません。' unless owner.id == actor.id || actor.usage_manager?

      items = Item.where(id: ids).order(:id).lock.to_a
      raise Invalid, '選択した対象が変更されています。選択し直してください。' unless items.map(&:id) == ids.sort

      now = Time.current
      start = immediate ? now : starts_at
      validate_period!(start, ends_at, now)
      if reason.present? && items.all?(&:reason_policy_none?)
        raise Invalid, '選択した対象には利用理由を入力できません。'
      end
      items.map do |item|
        check_item!(item)
        reject_overlap!(item, start, ends_at)
        item.usages.create!(user: owner, created_by: actor, updated_by: actor,
                            usage_kind: 'reservation', starts_at: start, ends_at: ends_at,
                            reason: item.reason_policy_none? ? nil : reason)
      end
    end
  end

  def self.update!(id, actor:, starts_at:, ends_at:, reason: KEEP_REASON)
    with_reservation(id, actor) do |usage, item, now|
      check_item!(item)
      raise Invalid, '無効な利用者の予約は変更できません。取消または利用終了してください。' if usage.user.nil? || usage.user.disabled?
      raise Invalid, '終了・取消済みの予約は変更できません。' unless [:scheduled, :active].include?(usage.reservation_state(now: now))

      if usage.starts_at <= now
        raise Invalid, '予約時間内の開始日時は変更できません。' unless starts_at == usage.starts_at
        raise Invalid, '終了日時は現在より後にしてください。' unless valid_time?(ends_at) && ends_at > now
      else
        validate_period!(starts_at, ends_at, now)
      end
      reject_overlap!(item, starts_at, ends_at, excluding: usage.id)
      previous = usage.attributes.slice('starts_at', 'ends_at', 'reason')
      reason = usage.reason if reason.equal?(KEEP_REASON)
      usage.update!(starts_at: starts_at, ends_at: ends_at, reason: reason,
                    updated_by: actor, updated_by_name_snapshot: actor.name)
      Change.new(usage: usage, previous: previous)
    end
  end

  def self.cancel!(id, actor:)
    with_reservation(id, actor) do |usage, _, now|
      raise Invalid, '開始前の予約のみ取り消せます。' unless usage.reservation_state(now: now) == :scheduled

      usage.update!(cancelled_at: now, cancelled_by: actor, cancelled_by_name_snapshot: actor.name,
                    updated_by: actor, updated_by_name_snapshot: actor.name)
      usage
    end
  end

  def self.finish!(id, actor:)
    with_reservation(id, actor) do |usage, _, now|
      raise Invalid, '予約時間内のみ利用終了できます。' unless usage.reservation_state(now: now) == :active

      usage.finish!(actor, now: now)
      usage
    end
  end

  def self.with_reservation(id, actor)
    Item.transaction do
      authorize_actor!(actor)
      reference = Usage.reservations.find(id)
      item = Item.lock.find(reference.item_id)
      usage = Usage.reservations.find(id)
      unless usage.user_id == actor.id || actor.usage_manager?
        raise Forbidden, '他の利用者の予約を操作する権限がありません。'
      end
      yield usage, item, Time.current
    end
  end

  def self.normalize_ids(item_ids)
    unless item_ids.is_a?(Array) && item_ids.any? && item_ids.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) }
      raise Invalid, '予約する対象を選択してください。'
    end
    ids = item_ids.map(&:to_i)
    raise Invalid, '同じ対象を重複して選択できません。' unless ids.uniq.length == ids.length

    ids
  end

  def self.authorize_actor!(actor)
    actor.reload
    raise Forbidden, '無効なアカウントでは操作できません。' if actor.disabled?
  end

  def self.check_item!(item)
    raise Invalid, "#{item.name}は利用停止中です。" if item.disabled?
    raise Invalid, "#{item.name}は期間予約方式ではありません。" unless item.usage_mode_reservation?
  end

  def self.valid_time?(value)
    value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
  end

  def self.validate_period!(starts_at, ends_at, now)
    unless valid_time?(starts_at) && valid_time?(ends_at) && starts_at >= now && ends_at > starts_at
      raise Invalid, '開始は現在以降、終了は開始より後の日時を指定してください。'
    end
  end

  def self.reject_overlap!(item, starts_at, ends_at, excluding: nil)
    overlap = item.usages.overlapping(starts_at, ends_at)
    overlap = overlap.where.not(id: excluding) if excluding
    conflict = overlap.order(:starts_at, :id).first
    return unless conflict

    period = "#{I18n.l(conflict.starts_at, format: :timestamp)} ～ #{I18n.l(conflict.ends_at, format: :timestamp)}"
    raise Invalid, "#{item.name}は#{period}の予約と重複します。既存予約を変更するか、別の期間を指定してください。"
  end

  private_class_method :with_reservation, :normalize_ids, :authorize_actor!, :check_item!,
                       :valid_time?, :validate_period!, :reject_overlap!
end
