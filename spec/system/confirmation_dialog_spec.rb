require 'rails_helper'

RSpec.describe 'Shared confirmation dialog', type: :system do
  it 'keeps deletion safe on Escape, returns focus and displays names as plain text on a phone' do
    user = create_user(admin: true)
    item = Item.create!(name: '<b>貸出用端末A</b>')
    page.current_window.resize_to(390, 900)
    login(user)
    visit admin_items_path
    click_button '削除'
    dialog = find('#action-confirmation[open]')
    expect(dialog).to have_content(item.name)
    expect(dialog).not_to have_css('b')
    expect(dialog).to have_css('button:focus', text: '戻る')
    expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
    dialog.send_keys(:escape)
    expect(page).not_to have_css('#action-confirmation[open]')
    expect(Item.exists?(item.id)).to be(true)
    expect(page).to have_css('button:focus', text: '削除')
    dismiss_action_confirmation { click_button '削除' }
    expect(Item.exists?(item.id)).to be(true)
    accept_action_confirmation { click_button '削除' }
    expect(page).to have_content('削除しました')
    expect(Item.exists?(item.id)).to be(false)
  end
end
