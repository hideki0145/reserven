class Item < ApplicationRecord
  has_one :status, dependent: :destroy

  validates :name, presence: true
end
