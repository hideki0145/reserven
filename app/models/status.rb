class Status < ApplicationRecord
  belongs_to :item
  belongs_to :user

  def use?(user_id)
    use_flg && (Time.current < expires_at || self.user_id == user_id)
  end

  def grace_period?
    use_flg && (expires_at <= Time.current && Time.current < expires_at.since(15.minutes))
  end

  def set(user_id, expires_at)
    self.user_id = user_id
    self.use_flg = true
    self.expires_at = expires_at
    save!
  end

  def reset
    self.use_flg = false
    save!
  end
end
