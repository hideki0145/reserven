class Item < ApplicationRecord
  include Sequenced
  has_many :usages, dependent: :nullify
  has_one :current_usage, -> { immediates.unfinished.order(id: :desc) }, class_name: 'Usage'

  validates :name, presence: true
  enum :reason_policy, { none: 'none', optional: 'optional', required: 'required' }, prefix: true, validate: true
  enum :usage_mode, { immediate: 'immediate', reservation: 'reservation' }, prefix: true, validate: true
  validate :protect_usage_mode, if: -> { persisted? && will_save_change_to_usage_mode? }

  scope :visible_on_status, -> {
    left_joins(:current_usage).where('items.disabled = ? OR usages.id IS NOT NULL', false)
  }

  before_destroy :reject_deletion_while_in_use, prepend: true

  def usage_state(user_id, now: Time.current)
    return :stopped if disabled?
    return :available unless current_usage&.unfinished?
    return :grace_period if current_usage.grace_period?(now: now)
    return :in_use if current_usage.ends_at > now

    current_usage.user_id == user_id ? :expired : :available
  end

  def can_start_usage?(user_id, now: Time.current)
    usage_mode_immediate? && usage_state(user_id, now: now) == :available
  end

  def can_extend_usage?(user_id, manager: false)
    !disabled? && can_end_usage?(user_id, manager: manager) && current_usage.user&.disabled? == false
  end

  def can_end_usage?(user_id, manager: false)
    !!(current_usage&.unfinished? && (current_usage.user_id == user_id || manager))
  end

  # The caller holds the item's lock while checking availability and starting usage.
  def start_usage!(user, ends_at, reason: nil)
    raise ArgumentError, '期間予約方式では即時利用用の処理を呼び出せません。' unless usage_mode_immediate?

    transaction do
      current_usage&.finish!(user, reason: 'reassigned')
      usages.create!(user: user, starts_at: Time.current, ends_at: ends_at, reason: reason)
    end.tap { association(:current_usage).reset }
  end

  private

  def protect_usage_mode
    if usages.outstanding.exists?
      errors.add(:usage_mode, 'は利用中または有効な予約があるため変更できません。')
    end
  end

  def reject_deletion_while_in_use
    if usages.reservations.outstanding.exists?
      errors.add(:base, '有効な予約があるため削除できません。予約を整理するか、無効化してください。')
      throw :abort
    end
    return unless current_usage&.unfinished?

    errors.add(:base, '利用中の対象は削除できません。利用終了後に削除するか、無効化してください。')
    throw :abort
  end
end
