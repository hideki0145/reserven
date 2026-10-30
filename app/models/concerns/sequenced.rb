module Sequenced
  extend ActiveSupport::Concern

  included do
    scope :in_order, -> { order(:seq, :id) }
    validates :seq, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    before_create :append_to_sequence
  end

  private

  def append_to_sequence
    self.seq = self.class.maximum(:seq).to_i + 1 if seq.zero?
  end
end
