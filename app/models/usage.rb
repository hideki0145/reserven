class Usage < ApplicationRecord
  belongs_to :item, optional: true
  belongs_to :user, optional: true
  belongs_to :finished_by, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  scope :unfinished, -> { where(finished_at: nil) }
  normalizes :reason, with: ->(value) { value.strip.presence }

  before_validation :capture_name_snapshots, on: :create
  validates :item, :user, presence: true, on: :create
  validates :created_by, :updated_by, presence: true, on: :create
  validates :item_name_snapshot, :user_name_snapshot, :starts_at, :ends_at, presence: true
  validates :ends_at, comparison: { greater_than: :starts_at }, if: -> { starts_at && ends_at }
  validates :finish_reason, inclusion: { in: %w[returned reassigned] }, allow_nil: true
  validates :finish_reason, :finished_by_name_snapshot, presence: true, if: :finished_at?
  validates :reason, length: { maximum: 500 }
  validate :reason_matches_policy, on: :create

  def unfinished?
    finished_at.nil?
  end

  def grace_period?(now: Time.current)
    unfinished? && ends_at <= now && now < ends_at.since(15.minutes)
  end

  def finish!(actor, reason: 'returned')
    # Preserve the operator's name at the finish operation.
    update!(finished_at: Time.current, finish_reason: reason,
            finished_by: actor, finished_by_name_snapshot: actor.name,
            updated_by: actor, updated_by_name_snapshot: actor.name)
  end

  def extend!(ends_at, actor)
    update!(ends_at: ends_at, updated_by: actor, updated_by_name_snapshot: actor.name)
  end

  private

  def reason_matches_policy
    return unless item

    errors.add(:reason, 'を入力してください。') if item.reason_policy_required? && reason.blank?
    errors.add(:reason, 'はこの対象では入力できません。') if item.reason_policy_none? && reason.present?
  end

  def capture_name_snapshots
    # Preserve names at record creation, independently of later renames or deletion.
    self.item_name_snapshot ||= item&.name
    self.user_name_snapshot ||= user&.name
    self.created_by ||= user
    self.updated_by ||= created_by
    self.created_by_name_snapshot ||= created_by&.name
    self.updated_by_name_snapshot ||= updated_by&.name
  end
end
