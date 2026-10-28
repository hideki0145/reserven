class Item < ApplicationRecord
  has_one :status, dependent: :destroy

  validates :name, presence: true

  scope :visible_on_status, -> {
    left_joins(:status).where('items.disabled = ? OR statuses.use_flg = ?', false, true)
  }

  before_destroy :reject_deletion_while_in_use, prepend: true

  private

  def reject_deletion_while_in_use
    return unless status&.use_flg?

    errors.add(:base, '利用中のアイテムは削除できません。利用終了後に削除するか、無効化してください。')
    throw :abort
  end
end
