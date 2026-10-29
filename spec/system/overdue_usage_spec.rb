require 'rails_helper'

RSpec.describe 'Overdue usage display', type: :system do
  [1440, 390].each do |width|
    it "shows overdue usage and preserves actions at #{width}px" do
      travel_to(Time.zone.local(2026, 10, 29, 12, 0)) do
        owner = create_user
        own_item = Item.create!(name: '自分の期限切れPC')
        other_item = Item.create!(name: '他の人の期限切れPC')
        stopped_item = Item.create!(name: '利用停止中のPC', disabled: true)
        [[own_item, owner], [other_item, create_user], [stopped_item, owner]].each do |item, user|
          create_usage(item: item, user: user, active: true, expires_at: 30.minutes.ago)
        end
        page.current_window.resize_to(width, 900)
        login(owner)

        within('tr', text: own_item.name) do
          expect(page).to have_css('.badge.text-bg-danger', text: '⏰ 期限切れ')
          expect(page).to have_content('他の利用者は利用を開始できます。')
          expect(page).to have_content('利用期限: 10/29(木) 11:30')
          expect(page).to have_button('延長する')
          expect(page).to have_button('利用終了')
        end
        within('tr', text: other_item.name) do
          expect(page).to have_content('✅ 利用可能')
          expect(page).not_to have_content('他の利用者は利用を開始できます。')
          expect(page).to have_button('利用する')
        end
        within('tr', text: stopped_item.name) do
          expect(page).to have_content('利用停止中')
          expect(page).not_to have_content('他の利用者は利用を開始できます。')
          expect(page).not_to have_button('延長する')
          expect(page).to have_button('利用終了')
        end
        expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
        within('tr', text: own_item.name) { click_button '延長する' }
        within('tr', text: own_item.name) do
          expect(page).to have_content('🔵 利用中')
          expect(page).not_to have_content('他の利用者は利用を開始できます。')
          click_button '利用終了'
        end
        within('tr', text: own_item.name) { expect(page).to have_content('✅ 利用可能') }
      end
    end
  end
end
