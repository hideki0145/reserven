class Usage < ApplicationRecord
  belongs_to :item, optional: true
  belongs_to :user, optional: true
  belongs_to :finished_by, class_name: 'User', optional: true

  scope :unfinished, -> { where(finished_at: nil) }

  before_validation :capture_name_snapshots, on: :create
  validates :item, :user, presence: true, on: :create
  validates :item_name_snapshot, :user_name_snapshot, :starts_at, :ends_at, presence: true
  validates :ends_at, comparison: { greater_than: :starts_at }, if: -> { starts_at && ends_at }
  validates :finish_reason, inclusion: { in: %w[returned reassigned] }, allow_nil: true
  validates :finish_reason, :finished_by_name_snapshot, presence: true, if: :finished_at?

  def unfinished?
    finished_at.nil?
  end

  def grace_period?(now: Time.current)
    unfinished? && ends_at <= now && now < ends_at.since(15.minutes)
  end

  def finish!(actor, reason: 'returned')
    # Preserve the operator's name at the finish operation.
    update!(finished_at: Time.current, finish_reason: reason,
            finished_by: actor, finished_by_name_snapshot: actor.name)
  end

  private

  def capture_name_snapshots
    # Preserve names at record creation, independently of later renames or deletion.
    self.item_name_snapshot ||= item&.name
    self.user_name_snapshot ||= user&.name
  end
end
