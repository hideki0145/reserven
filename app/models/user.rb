class User < ApplicationRecord
  attr_accessor :remember_token

  has_secure_password

  has_many :statuses, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

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
    return false if remember_digest.nil?

    BCrypt::Password.new(remember_digest).is_password?(remember_token)
  end

  def self.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  def self.new_token
    SecureRandom.urlsafe_base64
  end
end
