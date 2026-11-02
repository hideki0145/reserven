require 'rails_helper'

RSpec.describe 'Concurrent period reservations', type: :request do
  self.use_transactional_tests = false

  it 'commits only one overlapping batch when users select the same targets in opposite orders' do
    users = [create_user, create_user]
    items = [Item.create!(name: '貸出用端末A', usage_mode: 'reservation'),
             Item.create!(name: '貸出用端末B', usage_mode: 'reservation')]
    ready = Queue.new
    start = Queue.new
    from = 1.day.from_now
    to = from + 1.hour
    workers = users.each_with_index.map do |user, index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            ReservationBooking.create!(actor: user, item_ids: (index.zero? ? items : items.reverse).map(&:id),
                                       starts_at: from, ends_at: to)
            :success
          rescue ReservationBooking::Invalid
            :conflict
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(workers.map(&:value).sort).to eq([:conflict, :success])
    rows = Usage.where(item: items)
    expect(rows.count).to eq(2)
    expect(rows.distinct.pluck(:user_id).length).to eq(1)
  ensure
    workers&.each(&:join)
    if items
      rows = Usage.where(item: items)
      ids = rows.pluck(:id)
      rows.update_all(cancelled_at: Time.current)
      items.each(&:destroy!)
    end
    users&.each(&:destroy!)
    Usage.where(id: ids).delete_all if ids
  end
end
