require 'rails_helper'

RSpec.describe 'Reason input', type: :system do
  it 'pauses refresh while entering a reason and retains it when cancelling an overnight modal' do
    travel_to(Time.zone.local(2026, 10, 30, 23, 50)) do
      user = create_user
      Item.create!(name: '貸出用端末A', reason_policy: 'required')
      page.current_window.resize_to(390, 900)
      login(user)
      fill_in '利用理由(必須)', with: '夜間検証'
      expect(page).to have_content('入力中のため自動更新を停止しています。')
      click_button '利用する'
      expect(page).to have_css('dialog[open]')
      click_button '戻る'
      expect(find('textarea').value).to eq('夜間検証')
      click_button '利用する'
      click_button '確定する'
      expect(page).to have_content('利用理由: 夜間検証')
      click_button '利用終了'
      visit usage_histories_path
      expect(page).to have_content('利用理由: 夜間検証')
      expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
    end
  end
end
