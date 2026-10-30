class Usage < ApplicationRecord
  belongs_to :item, optional: true
  belongs_to :user, optional: true
  belongs_to :finished_by, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  belongs_to :cancelled_by, class_name: 'User', optional: true

  enum :usage_kind, { immediate: 'immediate', reservation: 'reservation' }, prefix: true, validate: true
  scope :immediates, -> { where(usage_kind: 'immediate') }
  scope :reservations, -> { where(usage_kind: 'reservation') }
  scope :not_cancelled, -> { where(cancelled_at: nil) }
  scope :outstanding, ->(now = Time.current) {
    unfinished.not_cancelled.where('usage_kind = ? OR ends_at > ?', 'immediate', now)
  }
  scope :history_at, ->(now = Time.current) {
    where('finished_at IS NOT NULL OR cancelled_at IS NOT NULL OR (usage_kind = ? AND ends_at <= ?)', 'reservation', now)
  }
  scope :overlapping, ->(starts_at, ends_at) {
    reservations.not_cancelled.where('starts_at < ? AND ends_at > ? AND (finished_at IS NULL OR finished_at > ?)',
                                    ends_at, starts_at, starts_at)
  }

  scope :unfinished, -> { where(finished_at: nil) }
  normalizes :reason, with: ->(value) { value.strip.presence }

  before_validation :capture_name_snapshots, on: :create
  validates :item, :user, presence: true, on: :create
  validates :created_by, :updated_by, presence: true, on: :create
  validates :item_name_snapshot, :user_name_snapshot, :starts_at, :ends_at, presence: true
  validates :ends_at, comparison: { greater_than: :starts_at }, if: -> { starts_at && ends_at }
  validates :finish_reason, inclusion: { in: %w[returned reassigned] }, allow_nil: true
  validates :finish_reason, :finished_by_name_snapshot, presence: true, if: :finished_at?
  validates :cancelled_by_name_snapshot, presence: true, if: :cancelled_at?
  validates :reason, length: { maximum: 500 }
  validate :reason_matches_policy, on: :create
  validate :reason_matches_snapshot, on: :update, if: -> { usage_kind_reservation? && will_save_change_to_reason? }

  def unfinished?
    finished_at.nil? && cancelled_at.nil?
  end

  def grace_period?(now: Time.current)
    usage_kind_immediate? && unfinished? && ends_at <= now && now < ends_at.since(15.minutes)
  end

  def finish!(actor, reason: 'returned', now: Time.current)
    # Preserve the operator's name at the finish operation.
    update!(finished_at: now, finish_reason: reason,
            finished_by: actor, finished_by_name_snapshot: actor.name,
            updated_by: actor, updated_by_name_snapshot: actor.name)
  end

  def extend!(ends_at, actor)
    update!(ends_at: ends_at, updated_by: actor, updated_by_name_snapshot: actor.name)
  end

  def reservation_state(now: Time.current)
    return :cancelled if cancelled_at
    return :finished if finished_at
    return :completed if ends_at <= now

    starts_at > now ? :scheduled : :active
  end

  def history_time
    cancelled_at || finished_at || ends_at
  end

  def completion_label
    return '予約取消' if cancelled_at
    return '予約期間終了' if usage_kind_reservation? && finished_at.nil?
    return '別の利用への切替' if finish_reason == 'reassigned'

    usage_kind_reservation? ? '途中終了' : '利用終了'
  end

  private

  def reason_matches_policy
    return unless item

    errors.add(:reason, 'を入力してください。') if item.reason_policy_required? && reason.blank?
    errors.add(:reason, 'はこの対象では入力できません。') if item.reason_policy_none? && reason.present?
  end

  def reason_matches_snapshot
    errors.add(:reason, 'を入力してください。') if reason_policy_snapshot == 'required' && reason.blank?
    errors.add(:reason, 'はこの予約では入力できません。') if reason_policy_snapshot == 'none' && reason.present?
  end

  def capture_name_snapshots
    # Preserve names at record creation, independently of later renames or deletion.
    self.item_name_snapshot ||= item&.name
    self.user_name_snapshot ||= user&.name
    self.created_by ||= user
    self.updated_by ||= created_by
    self.created_by_name_snapshot ||= created_by&.name
    self.updated_by_name_snapshot ||= updated_by&.name
    self.reason_policy_snapshot ||= item&.reason_policy
  end
end
