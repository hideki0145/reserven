require 'rails_helper'

RSpec.describe 'Reservation edit conflicts', type: :request do
  around do |example|
    travel_to(Time.zone.local(2026, 11, 2, 8)) { example.run }
  end

  it 'rejects an old form including after an invalid submission, without overwriting or notifying' do
    owner = create_user
    manager = create_user(usage_manager: true)
    item = Item.create!(name: '貸出用端末A', usage_mode: 'reservation', reason_policy: 'optional')
    usage = ReservationBooking.create!(actor: owner, item_ids: [item.id], starts_at: 1.day.from_now.change(sec: 0),
                                       ends_at: 2.days.from_now.change(sec: 0), reason: '当初の確認').sole
    login(manager)
    get edit_reservation_path(usage)
    version = Nokogiri::HTML(response.body).at_css('[name="reservation[lock_version]"]')['value']
    input = { lock_version: version, starts_at: usage.starts_at.strftime('%Y-%m-%dT%H:%M'),
              ends_at: usage.ends_at.strftime('%Y-%m-%dT%H:%M'), reason: usage.reason }
    ReservationBooking.update!(usage.id, actor: owner, starts_at: usage.starts_at, ends_at: usage.ends_at,
                               expected_version: usage.lock_version, reason: '変更後の確認')
    patch reservation_path(usage), params: { reservation: input.merge(ends_at: 'invalid') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).at_css('[name="reservation[lock_version]"]')['value']).to eq(version)
    allow(SlackNotifier).to receive(:deliver).and_return(true)
    patch reservation_path(usage), params: { reservation: input, return_to: 'status' }
    expect(response).to redirect_to(edit_reservation_path(usage, return_to: 'status'))
    expect(flash[:alert]).to include('予約が変更されています')
    expect(usage.reload.reason).to eq('変更後の確認')
    [nil, 'invalid', '-1'].each do |bad_version|
      patch reservation_path(usage), params: { reservation: input.merge(lock_version: bad_version) }
      expect(response).to redirect_to(edit_reservation_path(usage))
      expect(usage.reload.reason).to eq('変更後の確認')
    end
    expect(SlackNotifier).not_to have_received(:deliver)
    get edit_reservation_path(usage)
    new_version = Nokogiri::HTML(response.body).at_css('[name="reservation[lock_version]"]')['value']
    allow(SlackNotifier).to receive(:deliver).and_return(true)
    patch reservation_path(usage), params: { reservation: input.merge(lock_version: new_version, reason: '最新画面での確認') }
    expect(response).to redirect_to(reservations_path)
    expect(usage.reload.reason).to eq('最新画面での確認')
  end
end
