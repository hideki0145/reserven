require 'rails_helper'

RSpec.describe 'History screen', type: :system do
  it 'shows cards on phones and preserves the member filter when moving pages' do
    user = create_user
    item = Item.create!(name: '貸出用端末A')
    26.times { create_usage(item: item, user: user, active: false) }
    page.current_window.resize_to(390, 900)
    login(user)
    visit usage_histories_path
    select '自分', from: '利用者'
    click_button '絞り込む'
    expect(page).to have_css('.history-table tbody tr', count: 25)
    expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
    click_link '次へ'
    expect(page).to have_css('.history-table tbody tr', count: 1)
    expect(page).to have_select('利用者', selected: '自分')
    find('summary').click
    expect(page).to have_content("登録者: #{user.name}")
    page.current_window.resize_to(1440, 900)
    expect(page).to have_css('.history-table', style: { 'display' => 'table' })
  end
end
