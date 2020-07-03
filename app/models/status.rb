class Status < ApplicationRecord
  belongs_to :item
  belongs_to :user

  def use?
    use_flg && Time.current < expires_at
  end
end
