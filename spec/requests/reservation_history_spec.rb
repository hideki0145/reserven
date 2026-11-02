require 'rails_helper'

RSpec.describe 'Completed reservation history', type: :request do
  it 'shows natural expiry and cancellation without inventing an operator and excludes pending reservations' do
    user = create_user
    item = Item.create!(name: '貸出用端末A', usage_mode: 'reservation')
    travel_to(Time.zone.local(2026, 10, 30, 12)) do
      usage = ReservationBooking.create!(actor: user, item_ids: [item.id], starts_at: 1.hour.from_now, ends_at: 2.hours.from_now).sole
      login(user)
      get usage_histories_path
      expect(response.body).not_to include('<strong>貸出用端末A</strong>')
      travel 2.hours
      get usage_histories_path
      expect(response.body).to include('予約期間終了', '操作なし(期間終了)', '<strong>貸出用端末A</strong>')
      expect(usage.reload.finished_at).to be_nil
    end
  end
end
