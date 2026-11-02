module SystemSpecHelper
  def login(user)
    visit login_path
    fill_in 'session_email', with: user.email
    fill_in 'session_password', with: 'test-password'
    click_on 'ログインする'
  end

  def accept_action_confirmation(message = nil)
    yield
    dialog = find('#action-confirmation[open]')
    expect(dialog).to have_content(message) if message
    within(dialog) { click_button '確定する' }
    expect(page).not_to have_css('#action-confirmation[open]')
  end

  def dismiss_action_confirmation(message = nil)
    yield
    dialog = find('#action-confirmation[open]')
    expect(dialog).to have_content(message) if message
    within(dialog) { click_button '戻る' }
    expect(page).not_to have_css('#action-confirmation[open]')
  end

end
