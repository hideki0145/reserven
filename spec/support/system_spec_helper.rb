module SystemSpecHelper
  def login(user)
    visit login_path
    fill_in 'session_email', with: user.email
    fill_in 'session_password', with: 'test-password'
    click_on 'ログインする'
  end
end
