require 'rails_helper'

RSpec.describe 'Browser usage', type: :system do
  it 'logs in, starts and ends usage, then logs out' do
    travel_to(Time.zone.local(2026, 10, 28, 19, 30))
    user = create_user
    Item.create!(name: '会議室')
    login(user)
    expect(page).to have_css('.status-table', style: { 'display' => 'table' })
    expect(page).not_to have_css('[data-navigation-toggle]')
    expect(page).to have_link('利用状況')
    expect(page).to have_css('.badge', text: '✅ 利用可能')
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.btn-primary')).backgroundColor")).to eq('rgb(0, 123, 255)')
    click_button '利用する'
    expect(page).to have_css('.badge.bg-primary-subtle.text-primary-emphasis', text: '🔵 利用中')
    expect(page).to have_content("#{user.name}(自分)")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.btn-success')).backgroundColor")).to eq('rgb(40, 167, 69)')
    click_button '利用終了'
    expect(page).to have_css('.badge', text: '✅ 利用可能')
    dismiss_confirm('ログアウトします。よろしいですか？') { click_button 'ログアウト' }
    expect(page).to have_content(user.name)
    expect(page).to have_button('ログアウト')
    accept_confirm('ログアウトします。よろしいですか？') { click_button 'ログアウト' }
    expect(page).to have_current_path(login_path)
  ensure
    travel_back
  end

  it 'shows cards without horizontal scrolling and supports usage on a narrow screen' do
    travel_to(Time.zone.local(2026, 10, 28, 19, 30)) do
      user = create_user
      other_user = create_user(name: 'LongUserName' * 12)
      available = Item.create!(name: '持ち出し用ノートPC-' * 12)
      active = Item.create!(name: '利用中のPC')
      grace = Item.create!(name: '猶予期間中のPC')
      disabled = Item.create!(name: '利用中に無効化したPC', disabled: true)
      hidden = Item.create!(name: '無効で未利用のPC', disabled: true)
      Status.create!(item: active, user: other_user, expires_at: 30.minutes.from_now, use_flg: true)
      Status.create!(item: grace, user: other_user, expires_at: 5.minutes.ago, use_flg: true)
      Status.create!(item: disabled, user: user, expires_at: 30.minutes.from_now, use_flg: true)
      page.current_window.resize_to(390, 844)
      login(user)

      within('tr', text: available.name) do
        expect(page).to have_css('.badge', text: '✅ 利用可能')
        expect(page).to have_button('利用する')
        fill_in '利用期限', with: '19:50'
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
      within('tr', text: disabled.name) do
        expect(page).to have_content('利用停止中')
        expect(page).to have_button('利用終了')
        expect(page).not_to have_button('延長する')
      end
      expect(page).not_to have_content(hidden.name)
      [320, 390, 767].each do |width|
        page.current_window.resize_to(width, 844)
        expect(page).to have_css('.status-table tbody tr', style: { 'display' => 'block' }, count: 4)
        expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
        expect(page.evaluate_script("document.querySelector('.status-list').scrollWidth <= document.querySelector('.status-list').clientWidth")).to be(true)
      end
      page.current_window.resize_to(390, 844)
      within('tr', text: available.name) do
        expect(find('input[type="time"]').value).to eq('19:50')
        click_button '利用する'
      end
      within('tr', text: available.name) do
        expect(page).to have_content('利用期限: 10/28(水) 19:50')
        fill_in '延長後の利用期限', with: '20:00'
        click_button '延長する'
      end
      within('tr', text: available.name) do
        expect(page).to have_content('利用期限: 10/28(水) 20:00')
        click_button '利用終了'
      end
      within('tr', text: available.name) do
        expect(page).to have_content('✅ 利用可能')
      end
      page.current_window.resize_to(768, 900)
      expect(page).to have_css('.status-table', style: { 'display' => 'table' })
      expect(page).to have_css('.status-table tbody tr', style: { 'display' => 'table-row' }, count: 4)
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
    expect(page).not_to have_link('ユーザ一覧')
    find('[data-navigation-toggle]').click
    expect(find('[data-navigation-toggle]')['aria-expanded']).to eq('true')
    find('[data-navigation-toggle]').send_keys(:escape)
    expect(page).not_to have_link('ユーザ一覧')
    find('[data-navigation-toggle]').click
    click_link 'ユーザ一覧'
    expect(page).to have_content('ユーザ一覧')
    expect(page).to have_css('h1.h4', text: 'ユーザ一覧')
    expect(page).to have_css('.table-responsive table')
    expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
    find('[data-navigation-toggle]').click
    click_link 'アイテム一覧'
    expect(page).to have_content('アイテム一覧')
    expect(page).to have_css('h1.h4', text: 'アイテム一覧')
    find('[data-navigation-toggle]').click
    accept_confirm('ログアウトします。よろしいですか？') { click_button 'ログアウト' }
    expect(page).to have_current_path(login_path)
  end
end

RSpec.describe 'Deadline entry', type: :system do
  around do |example|
    travel_to(Time.zone.local(2026, 10, 28, 19, 30)) { example.run }
  end

  it 'uses time-only input and updates the day hint for input and change events' do
    Item.create!(name: '時刻入力のPC')
    login(create_user)
    expect(find('input[name="expires_at"]')[:type]).to eq('time')
    fill_in '利用期限', with: '00:10'
    expect(page).to have_css('[data-deadline-day]', exact_text: '翌日')
    fill_in '利用期限', with: '20:00'
    expect(page).to have_css('[data-deadline-day]', exact_text: '本日')
    # The driver dispatches a non-bubbling input event for Time values, followed by change.
    fill_in '利用期限', with: Time.zone.local(2026, 10, 28, 18)
    expect(page).to have_css('[data-deadline-day]', exact_text: '翌日')
  end

  it 'starts and extends across midnight only after confirmation, and supports returning' do
    travel_to(Time.zone.local(2026, 10, 28, 23, 55))
    item = Item.create!(name: '日付またぎのPC')
    page.current_window.resize_to(390, 844)
    login(create_user)
    expect(find('input[name="expires_at"]').value).to eq('00:10')
    expect(page).to have_css('[data-deadline-day]', exact_text: '翌日')
    click_button '利用する'
    expect(page).to have_content('翌日 10/29(木) 00:10')
    expect(item.reload.status).to be_nil
    expect(page).to have_css('dialog[open]')
    expect(page).to have_current_path(root_path)
    expect(find('dialog[open]')).not_to have_content('日本時間')
    expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
    find('dialog[open]').send_keys(:escape)
    expect(page).not_to have_css('dialog[open]')
    expect(item.reload.status).to be_nil
    click_button '利用する'
    click_button '戻る'
    expect(page).not_to have_css('dialog[open]')
    expect(page).to have_css('.badge', text: '✅ 利用可能')
    click_button '利用する'
    click_button '確定する'
    expect(page).to have_content('利用期限: 10/29(木) 00:10')
    expect(find('input[name="expires_at"]').value).to eq('00:25')
    click_button '延長する'
    expect(page).to have_content('翌日 10/29(木) 00:25')
    expect(item.reload.status.expires_at).to eq(Time.zone.local(2026, 10, 29, 0, 10))
    click_button '確定する'
    expect(page).to have_content('利用期限: 10/29(木) 00:25')
  end

  it 'starts same-day usage without confirmation' do
    item = Item.create!(name: '当日利用のPC')
    login(create_user)
    fill_in '利用期限', with: '20:00'
    click_button '利用する'
    expect(page).to have_content('利用期限: 10/28(水) 20:00')
    expect(item.reload.status.expires_at).to eq(Time.zone.local(2026, 10, 28, 20))
  end

  it 'rejects the current time without changing availability' do
    Item.create!(name: '入力確認のPC')
    login(create_user)
    fill_in '利用期限', with: '19:30'
    click_button '利用する'
    expect(page).to have_css('.alert-danger', text: '現在と同じ時刻は指定できません。')
    expect(page).to have_css('.badge', text: '✅ 利用可能')
  end
end
