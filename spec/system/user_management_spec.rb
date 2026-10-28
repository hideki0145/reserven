require 'rails_helper'

RSpec.describe 'User management screen', type: :system do
  it 'shows formatted dates and centered permissions, and rejects losing the last admin' do
    admin = create_user(admin: true, created_at: Time.zone.local(2026, 10, 28, 19, 30, 15))
    login(admin)
    click_link 'ユーザ一覧'
    expect(page).to have_content('2026/10/28 19:30:15')
    expect(page.evaluate_script("getComputedStyle(document.querySelector('tbody td.text-center')).textAlign")).to eq('center')
    click_link admin.name
    expect(page).to have_link('一覧', class: 'btn')
    click_link '編集'
    uncheck '管理者権限'
    click_button '更新する'
    expect(page).to have_content('有効な管理者を少なくとも1人残してください。')
    expect(admin.reload).to be_admin
    check '管理者権限'
    check 'アカウント無効'
    click_button '更新する'
    expect(page).to have_content('有効な管理者を少なくとも1人残してください。')
    expect(admin.reload).not_to be_disabled
  end

  it 'disables and reactivates an account from its edit screen on a narrow display' do
    admin = create_user(admin: true)
    other = create_user(name: '停止対象')
    login(admin)
    page.current_window.resize_to(390, 844)
    visit edit_admin_user_path(other)
    check 'アカウント無効'
    click_button '更新する'
    expect(page).to have_content('無効')
    expect(other.reload).to be_disabled
    expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
    click_link '編集'
    uncheck 'アカウント無効'
    click_button '更新する'
    expect(other.reload).not_to be_disabled
  end
end
