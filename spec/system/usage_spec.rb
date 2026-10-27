require 'rails_helper'

RSpec.describe 'Browser usage', type: :system do
  it 'logs in, starts and ends usage, then logs out' do
    user = create_user
    Item.create!(name: '会議室')
    login(user)
    expect(page).to have_content('未使用')
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.btn-primary')).backgroundColor")).to eq('rgb(0, 123, 255)')
    click_button '使用する'
    expect(page).to have_content('自分が')
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.btn-success')).backgroundColor")).to eq('rgb(40, 167, 69)')
    click_button '使用終了'
    expect(page).to have_content('未使用')
    click_button 'ログアウト'
    expect(page).to have_current_path(login_path)
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
