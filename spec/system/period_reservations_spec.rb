require 'rails_helper'

RSpec.describe 'Period reservation workflow', type: :system do
  around do |example|
    travel_to(Time.zone.local(2026, 10, 30, 12)) { example.run }
  end

  it 'registers multiple targets for another member and changes or cancels only one on a phone' do
    manager = create_user(name: '利用担当A', usage_manager: true)
    owner = create_user(name: '利用者B')
    a = Item.create!(name: '貸出用端末A', usage_mode: 'reservation')
    b = Item.create!(name: '貸出用端末B', usage_mode: 'reservation', reason_policy: 'required')
    page.current_window.resize_to(390, 900)
    login(manager)
    within('section', text: a.name) { click_link '期間を指定して予約' }
    check b.name
    select owner.name, from: '利用者'
    fill_in '開始日時', with: '2026-11-02T09:00'
    fill_in '終了日時', with: '2026-11-02T10:00'
    fill_in '利用理由', with: '共同検証'
    expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
    click_button '予約を登録する'
    expect(page).to have_content('2件の予約を登録しました。')
    within('tbody tr', text: b.name) { click_link '日時・理由の変更' }
    fill_in '終了日時', with: '2026-11-02T11:00'
    fill_in '利用理由(必須)', with: '変更後の検証'
    click_button '更新する'
    expect(page).to have_content('予約を更新しました。')
    dismiss_action_confirmation { within('tbody tr', text: b.name) { click_button '取消' } }
    expect(Usage.reservations.outstanding.count).to eq(2)
    accept_action_confirmation { within('tbody tr', text: b.name) { click_button '取消' } }
    expect(page).to have_content('予約を取り消しました。')
    expect(Usage.reservations.outstanding.count).to eq(1)
    expect(Usage.find_by!(item: b).cancelled_by).to eq(manager)
    expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
  end

  it 'starts now, extends without changing the actual start and ends immediately' do
    user = create_user
    item = Item.create!(name: '貸出用端末A', usage_mode: 'reservation', reason_policy: 'optional')
    login(user)
    within('section', text: item.name) { click_link '今すぐ利用' }
    expect(page).to have_css('#reservation_starts_at[readonly]')
    choose '日時を指定する'
    expect(page).to have_field('開始日時', disabled: false)
    expect(page).not_to have_css('#reservation_starts_at[readonly]')
    choose '今すぐ利用する'
    expect(page).to have_css('#reservation_starts_at[readonly]')
    fill_in '終了日時', with: '2026-10-30T13:00'
    fill_in '利用理由', with: '当日検証'
    click_button '予約を登録する'
    expect(page).to have_current_path(status_path)
    expect(page).to have_content('予約時間内')
    usage = Usage.reservations.sole
    click_link '期間・理由の変更'
    fill_in '終了日時', with: '2026-10-30T14:00'
    click_button '更新する'
    expect(page).to have_content('予約を更新しました。')
    expect(page).to have_current_path(status_path)
    expect(usage.reload.starts_at).to eq(Time.current)
    click_button '利用終了'
    expect(page).to have_content('利用終了しました。')
    expect(page).to have_current_path(status_path)
    click_link '利用履歴'
    expect(page).to have_content('途中終了')
    expect(page).to have_content('当日検証')
  end

  it 'preserves the specific usage when a manager confirms an overnight extension for another member' do
    travel_to(Time.zone.local(2026, 10, 30, 23, 30))
    owner = create_user(name: '利用者A')
    manager = create_user(name: '利用担当B', usage_manager: true)
    item = Item.create!(name: '貸出用端末A')
    usage = item.start_usage!(owner, Time.zone.local(2026, 10, 30, 23, 45))
    login(manager)
    fill_in '延長後の利用期限', with: '00:15'
    click_button '延長する'
    expect(page).to have_css('dialog[open]')
    click_button '確定する'
    expect(page).to have_content('利用延長します。')
    expect(usage.reload.updated_by).to eq(manager)
    click_button '利用終了'
    expect(page).to have_content('利用終了しました。')
    expect(usage.reload.finished_by).to eq(manager)
    expect(usage.user).to eq(owner)
  end

  it 'retains the start reference after a validation error for immediate booking and retries with server time' do
    user = create_user
    item = Item.create!(name: '貸出用端末A', usage_mode: 'reservation', reason_policy: 'optional')
    login(user)
    within('section', text: item.name) { click_link '今すぐ利用' }
    start = find('#reservation_starts_at').value
    expect(start).not_to be_empty
    fill_in '終了日時', with: '2026-10-30T11:00'
    fill_in '利用理由', with: '当日検証'
    travel_to(Time.zone.local(2026, 10, 30, 12, 5))
    click_button '予約を登録する'
    expect(page).to have_css('[role="alert"]')
    expect(page).to have_checked_field('今すぐ利用する')
    expect(page).to have_checked_field(item.name)
    expect(find('#reservation_starts_at').value).to eq(start)
    expect(page).to have_css('#reservation_starts_at[readonly]')
    expect(page).to have_field('終了日時', with: '2026-10-30T11:00')
    expect(page).to have_field('利用理由', with: '当日検証')
    choose '日時を指定する'
    expect(page).not_to have_css('#reservation_starts_at[readonly]')
    expect(find('#reservation_starts_at').value).to eq(start)
    choose '今すぐ利用する'
    fill_in '終了日時', with: '2026-10-30T13:00'
    click_button '予約を登録する'
    expect(page).to have_current_path(status_path)
    expect(Usage.sole.starts_at).to eq(Time.current)
    expect(Usage.sole.reason).to eq('当日検証')
  end

end
