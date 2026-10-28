require 'rails_helper'

RSpec.describe 'Item management screen', type: :system do
  it 'stops an occupied item, allows ending it and reactivates it' do
    user = create_user(admin: true)
    item = Item.create!(name: '貸出中PC', created_at: Time.zone.local(2026, 10, 28, 19, 30, 15))
    Status.create!(item: item, user: user, use_flg: true, expires_at: 30.minutes.from_now)
    login(user)
    click_link 'アイテム一覧'
    expect(page).to have_content('2026/10/28 19:30:15')
    click_link item.name
    expect(page).to have_link('一覧', class: 'btn')
    click_link '編集'
    check 'アイテム無効'
    click_button '更新する'
    visit status_path
    expect(page).to have_content('利用停止中')
    expect(page).not_to have_button('延長する')
    click_button '利用終了'
    expect(page).not_to have_css('tbody tr', text: item.name)
    visit edit_admin_item_path(item)
    uncheck 'アイテム無効'
    click_button '更新する'
    visit status_path
    expect(page).to have_content(item.name)
    expect(page).to have_button('利用する')
  end
end
