require 'rails_helper'

RSpec.describe 'Inactive filter choices', type: :system do
  [:history, :reservations].each do |screen|
    it "updates #{screen} choices independently on a phone, preserves selections and resets them on clear" do
      viewer = create_user
      owner = create_user(name: '利用者B')
      active = Item.create!(name: '貸出用端末A', usage_mode: 'reservation')
      stopped = Item.create!(name: '貸出用端末B', usage_mode: 'reservation')
      [active, stopped].each_with_index do |item, i|
        user = i.zero? ? viewer : owner
        if screen == :history
          create_usage(item: item, user: user, active: false)
        else
          ReservationBooking.create!(actor: user, item_ids: [item.id], starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)
        end
      end
      stopped.update!(disabled: true)
      owner.update!(disabled: true)
      page.current_window.resize_to(390, 900)
      login(viewer)
      visit(screen == :history ? usage_histories_path : reservations_path)
      target_label = screen == :history ? '利用停止中・削除済みを含める' : '利用停止中を含める'
      member_label = screen == :history ? '無効・削除済みを含める' : '無効なアカウントを含める'
      expect(page).not_to have_select('対象', with_options: ["#{stopped.name}(利用停止中)"])
      expect(page).to have_css('.history-table tbody tr', count: 2)
      check target_label
      expect(page).to have_select('対象', with_options: ["#{stopped.name}(利用停止中)"])
      expect(page).not_to have_select('利用者', with_options: ["#{owner.name}(アカウント無効)"])
      select "#{stopped.name}(利用停止中)", from: '対象'
      click_button '絞り込む'
      expect(page).to have_css('.history-table tbody tr', count: 1)
      check member_label
      expect(page).to have_select('対象', selected: "#{stopped.name}(利用停止中)")
      expect(page).to have_select('利用者', with_options: ["#{owner.name}(アカウント無効)"])
      select "#{owner.name}(アカウント無効)", from: '利用者'
      click_button '絞り込む'
      uncheck target_label
      expect(page).to have_select('対象', selected: 'すべて')
      expect(page).to have_select('利用者', selected: "#{owner.name}(アカウント無効)")
      expect(page).to have_css('.history-table tbody tr', count: 1)
      uncheck member_label
      expect(page).to have_select('利用者', selected: '全員')
      expect(page).to have_css('.history-table tbody tr', count: 2)
      check target_label
      expect(page).to have_select('対象', with_options: ["#{stopped.name}(利用停止中)"])
      check member_label
      expect(page).to have_select('利用者', with_options: ["#{owner.name}(アカウント無効)"])
      click_link 'クリア'
      expect(page).to have_unchecked_field(target_label)
      expect(page).to have_unchecked_field(member_label)
      expect(page).not_to have_select('対象', with_options: ["#{stopped.name}(利用停止中)"])
      expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
    end
  end
end
