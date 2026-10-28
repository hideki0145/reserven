require 'rails_helper'

RSpec.describe 'Browser usage', type: :system do
  it 'logs in, starts and ends usage, then logs out' do
    user = create_user
    Item.create!(name: '会議室')
    login(user)
    expect(page).to have_css('.badge', text: '✅ 利用可能')
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.btn-primary')).backgroundColor")).to eq('rgb(0, 123, 255)')
    click_button '利用する'
    expect(page).to have_css('.badge.bg-primary-subtle.text-primary-emphasis', text: '🔵 利用中')
    expect(page).to have_content("#{user.name}(自分)")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.btn-success')).backgroundColor")).to eq('rgb(40, 167, 69)')
    click_button '利用終了'
    expect(page).to have_css('.badge', text: '✅ 利用可能')
    click_button 'ログアウト'
    expect(page).to have_current_path(login_path)
  end

  it 'shows usage states and weekday deadlines on a narrow screen' do
    travel_to(Time.zone.local(2026, 10, 28, 19, 30)) do
      user = create_user
      other_user = create_user
      available = Item.create!(name: '利用可能なPC')
      active = Item.create!(name: '利用中のPC')
      grace = Item.create!(name: '猶予期間中のPC')
      Status.create!(item: active, user: other_user, expires_at: 30.minutes.from_now, use_flg: true)
      Status.create!(item: grace, user: other_user, expires_at: 5.minutes.ago, use_flg: true)
      page.current_window.resize_to(390, 844)
      login(user)

      within('tr', text: available.name) do
        expect(page).to have_css('.badge', text: '✅ 利用可能')
        expect(page).to have_button('利用する')
      end
      within('tr', text: active.name) do
        expect(page).to have_css('.badge.bg-primary-subtle.text-primary-emphasis', text: '🔵 利用中')
        expect(page).to have_content('利用期限: 10/28(水) 20:00')
        expect(page).not_to have_button('延長する')
      end
      within('tr', text: grace.name) do
        expect(page).to have_css('.badge', text: '🟠 猶予期間中')
        expect(page).to have_content('期限後15分の猶予期間中です。')
        expect(page).not_to have_button('利用する')
      end
      expect(page).to have_css('.table-responsive', style: { 'overflow-x' => 'auto' })
      expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
    end
  end

  it 'confirms deletion and supports cancelling it' do
    user = create_user(admin: true)
    item = Item.create!(name: '会議室')
    login(user)
    click_link 'アイテム一覧'
    dismiss_confirm { click_button '削除' }
    expect(page).to have_content(item.name)
    expect(Item.exists?(item.id)).to be(true)
    accept_confirm { click_button '削除' }
    expect(page).to have_content('削除しました')
    expect(Item.exists?(item.id)).to be(false)
  end

  it 'keeps navigation and wide tables usable on a narrow screen' do
    page.current_window.resize_to(390, 844)
    login(create_user(admin: true))
    click_link 'ユーザ一覧'
    expect(page).to have_content('ユーザ一覧')
    expect(page).to have_css('.table-responsive table')
    expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
    click_link 'アイテム一覧'
    expect(page).to have_content('アイテム一覧')
    click_button 'ログアウト'
    expect(page).to have_current_path(login_path)
  end
end
