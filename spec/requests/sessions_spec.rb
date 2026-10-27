require 'rails_helper'

RSpec.describe 'Sessions', type: :request do
  let(:user) { create_user }

  it 'redirects unauthenticated visitors to login' do
    get root_path
    expect(response).to redirect_to(login_path)
  end

  it 'serves pinned Bootstrap from the CDN with integrity checking and local application assets' do
    get login_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('application-', 'ログインする')
    stylesheets = Nokogiri::HTML(response.body).css('link[rel="stylesheet"]')
    bootstrap = stylesheets.first
    expect(bootstrap['href']).to eq('https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css')
    expect(bootstrap['integrity']).to eq('sha384-sRIl4kxILFvY47J16cr9ZwB07vP4J8+LH7qKQnuqkuIAvNWLzeN8tE5YBujZqJLB')
    expect(bootstrap['crossorigin']).to eq('anonymous')
    expect(stylesheets.last['href']).to start_with('/assets/application-')
  end

  it 'logs in and logs out' do
    login(user)
    expect(response).to redirect_to(root_path)
    get root_path
    expect(response.body).to include(user.name)
    delete logout_path
    expect(response).to redirect_to(login_path)
    get root_path
    expect(response).to redirect_to(login_path)
  end

  it 'rejects an invalid password and renders the form' do
    post login_path, params: { session: { email: user.email, password: 'incorrect' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('メールアドレスまたはパスワードが正しくありません。')
    get root_path
    expect(response).to redirect_to(login_path)
  end

  it 'remembers a user and revokes the token on logout' do
    login(user, remember: '1')
    expect(user.reload.remember_digest).to be_present
    expect(cookies['remember_token']).to be_present
    expect(cookies['user_id']).to be_present
    expect(response.headers['set-cookie'].to_s).to include('httponly')
    delete logout_path
    expect(user.reload.remember_digest).to be_nil
    expect(cookies['remember_token']).to be_blank
  end

  it 'restores login from persistent cookies in a new session' do
    login(user, remember: '1')
    persistent_cookies = %w[user_id remember_token].to_h { |key| [key, cookies[key]] }
    new_session = ActionDispatch::Integration::Session.new(Rails.application)
    new_session.get root_path, headers: { 'HTTP_COOKIE' => persistent_cookies.map { |key, value| "#{key}=#{value}" }.join('; ') }
    expect(new_session.response).to have_http_status(:ok)
    expect(new_session.response.body).to include(user.name)
  end

  it 'rejects a missing remember token without an exception' do
    login(user, remember: '1')
    new_session = ActionDispatch::Integration::Session.new(Rails.application)
    new_session.get root_path, headers: { 'HTTP_COOKIE' => "user_id=#{cookies['user_id']}" }
    expect(new_session.response.location).to eq('http://www.example.com/login')
  end
end
