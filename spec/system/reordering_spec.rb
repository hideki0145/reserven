require 'rails_helper'

RSpec.describe 'Ordering screen', type: :system do
  it 'allows reviewing, cancelling and saving an order with buttons on a phone' do
    login(create_user(admin: true))
    a = Item.create!(name: '貸出用端末A')
    b = Item.create!(name: '貸出用端末B', disabled: true)
    page.current_window.resize_to(390, 900)
    visit admin_items_path
    click_link '並び順変更'
    find('button[aria-label="貸出用端末Bを上へ"]').click
    expect(all('[data-ordering-row]').map { |row| row['data-record-id'].to_i }).to eq([b.id, a.id])
    expect(Item.in_order.pluck(:id)).to eq([a.id, b.id])
    click_link 'キャンセル'
    expect(Item.in_order.pluck(:id)).to eq([a.id, b.id])
    click_link '並び順変更'
    find('button[aria-label="貸出用端末Bを上へ"]').click
    expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
    click_button '保存する'
    expect(page).to have_content('並び順を保存しました。')
    expect(Item.in_order.pluck(:id)).to eq([b.id, a.id])
  end

  it 'allows dragging a user and saving the new order on desktop' do
    admin = create_user(admin: true, name: '管理者A')
    other = create_user(name: '利用者B')
    login(admin)
    visit reorder_admin_users_path
    page.driver.with_playwright_page do |browser_page|
      browser_page.locator('[data-ordering-row]').last.locator('.order-handle').drag_to(browser_page.locator('[data-ordering-row]').first, targetPosition: { x: 5, y: 5 })
    end
    expect(all('[data-ordering-row]').map { |row| row['data-record-id'].to_i }).to eq([other.id, admin.id])
    click_button '保存する'
    expect(User.in_order.pluck(:id)).to eq([other.id, admin.id])
  end
end
