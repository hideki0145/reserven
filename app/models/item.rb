class Item < ApplicationRecord
  has_one :status, dependent: :destroy

  validates :name, presence: true

  scope :visible_on_status, -> {
    left_joins(:status).where('items.disabled = ? OR statuses.use_flg = ?', false, true)
  }

  before_destroy :reject_deletion_while_in_use, prepend: true

  def usage_state(user_id)
    return :stopped if disabled?
    return :available unless status&.use_flg?
    return :grace_period if status.grace_period?
    return :in_use if status.expires_at > Time.current

    status.user_id == user_id ? :expired : :available
  end

  def can_start_usage?(user_id)
    usage_state(user_id) == :available
  end

  def can_extend_usage?(user_id)
    !disabled? && can_end_usage?(user_id)
  end

  def can_end_usage?(user_id)
    !!(status&.use_flg? && status.user_id == user_id)
  end

  private

  def reject_deletion_while_in_use
    return unless status&.use_flg?

    errors.add(:base, '利用中のアイテムは削除できません。利用終了後に削除するか、無効化してください。')
    throw :abort
  end
end
