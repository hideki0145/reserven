class User < ApplicationRecord
  attr_accessor :remember_token

  has_secure_password

  normalizes :email, with: ->(email) { email.strip.downcase }

  has_many :usages, dependent: :nullify
  has_many :finished_usages, class_name: 'Usage', foreign_key: :finished_by_id, dependent: :nullify

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  scope :active_admins, -> { where(admin: true, disabled: false) }

  before_destroy :reject_deletion_with_outstanding_usage, prepend: true
  before_update :protect_last_active_admin, if: -> {
    admin_in_database && !disabled_in_database && (!admin? || disabled?)
  }
  before_destroy :protect_last_active_admin, prepend: true, if: -> { admin_in_database && !disabled_in_database }
  before_update :revoke_remember_login, if: -> {
    will_save_change_to_password_digest? || (will_save_change_to_disabled? && disabled?)
  }

  def create_remember_digest
    self.remember_token = User.new_token
    self.remember_digest = User.digest(remember_token)
    save!
  end

  def delete_remember_digest
    self.remember_digest = nil
    save!
  end

  def authenticated?(remember_token)
    return false if disabled? || remember_digest.nil? || remember_token.blank?

    BCrypt::Password.new(remember_digest).is_password?(remember_token)
  end

  def self.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  def self.new_token
    SecureRandom.urlsafe_base64
  end

  private

  def reject_deletion_with_outstanding_usage
    return unless usages.unfinished.exists?

    errors.add(:base, '利用終了していないアイテムがあるため削除できません。利用終了後に削除するか、アカウントを無効化してください。')
    throw :abort
  end

  def protect_last_active_admin
    return if User.active_admins.where.not(id: id).exists?

    errors.add(:base, '有効な管理者を少なくとも1人残してください。')
    throw :abort
  end

  def revoke_remember_login
    self.remember_digest = nil
  end
end
