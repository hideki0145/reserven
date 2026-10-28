require 'rails_helper'

RSpec.describe 'Status refresh', type: :system do
  around do |example|
    travel_to(Time.zone.local(2026, 10, 28, 19, 30)) { example.run }
  end

  def prepare_page
    @item = Item.create!(name: '更新前のPC')
    login(create_user)
    page.driver.with_playwright_page { |browser_page| browser_page.clock.install }
    # Install the browser clock before registering the interval on this page.
    visit status_path
  end

  def advance_refresh_interval
    page.driver.with_playwright_page { |browser_page| browser_page.clock.fast_forward(600_001) }
  end

  it 'refreshes an untouched page after ten minutes and displays its update time' do
    prepare_page
    expect(page).to have_content('最終更新: 2026/10/28 19:30:00')
    @item.update!(name: '更新後のPC')
    advance_refresh_interval
    expect(page).to have_content('更新後のPC')
  end

  it 'preserves changed input across intervals and resumes when all fields are restored' do
    prepare_page
    Item.create!(name: '2台目')
    visit status_path
    fields = all('input[type="time"]')
    original = fields.first.value
    fields.first.set('20:00')
    fields.last.set('20:30')
    expect(page).to have_content('入力中のため自動更新を停止しています。')
    @item.update!(name: '更新後のPC')
    advance_refresh_interval
    expect(page).to have_content('更新前のPC')
    expect(find('input[type="time"]', match: :first).value).to eq('20:00')
    fields.first.set(original)
    expect(page).to have_content('入力中のため自動更新を停止しています。')
    fields.last.set(original)
    expect(page).not_to have_content('入力中のため自動更新を停止しています。')
    advance_refresh_interval
    expect(page).to have_content('更新後のPC')
  end

  it 'keeps input on cancellation and discards it only after manual confirmation' do
    prepare_page
    fill_in '利用期限', with: '20:00'
    @item.update!(name: '更新後のPC')
    dismiss_confirm { click_link '更新', exact: true }
    expect(find('input[type="time"]').value).to eq('20:00')
    expect(page).to have_content('更新前のPC')
    accept_confirm { click_link '更新', exact: true }
    expect(page).to have_content('更新後のPC')
    expect(find('input[type="time"]').value).to eq('19:45')
  end

  it 'refreshes untouched input manually without confirmation' do
    prepare_page
    @item.update!(name: '更新後のPC')
    click_link '更新', exact: true
    expect(page).to have_content('更新後のPC')
  end
  it 'does not reload an open overnight modal even when the input is unchanged' do
    travel_to(Time.zone.local(2026, 10, 28, 23, 55))
    prepare_page
    click_button '利用する'
    expect(page).to have_css('dialog[open]')
    @item.update!(name: '更新後のPC')
    advance_refresh_interval
    expect(page).to have_css('dialog[open]')
    expect(page).to have_content('更新前のPC')
    find('dialog[open]').send_keys(:escape)
    page.driver.with_playwright_page do |browser_page|
      browser_page.wait_for_function("() => !deadlineSubmissions.has(document.querySelector('[data-deadline-field] input').form)")
    end
    advance_refresh_interval
    expect(page).to have_content('更新後のPC')
  end
end
