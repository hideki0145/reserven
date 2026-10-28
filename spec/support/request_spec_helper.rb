module RequestSpecHelper
  def login(user, remember: '0')
    post login_path, params: {
      session: { email: user.email, password: 'test-password', remember_cookies: remember }
    }
  end
end
