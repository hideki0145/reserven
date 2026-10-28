require 'rails_helper'

RSpec.describe 'Login attempt limits', type: :request do
  let(:user) { create_user }
  let(:address) { '198.51.100.10' }

  def attempt(password: 'incorrect', ip: address)
    post login_path, params: { session: { email: user.email, password: password } },
                     headers: { 'REMOTE_ADDR' => ip }
  end

  it 'allows ten attempts and refuses the eleventh, including a correct password' do
    10.times do
      attempt
      expect(response).to have_http_status(:unprocessable_content)
    end
    attempt(password: 'test-password')
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After']).to eq('180')
    expect(response.body).to include('ログインの試行回数が上限に達しました。', 'ログインする')
    get status_path
    expect(response).to redirect_to(login_path)
  end

  it 'counts successful logins too' do
    10.times do
      attempt(password: 'test-password')
      expect(response).to redirect_to(root_path)
    end
    attempt(password: 'test-password')
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'restores access after the window expires without extending the window on rejection' do
    travel_to(Time.zone.local(2026, 10, 28, 19, 30)) do
      10.times { attempt }
      travel 179.seconds
      attempt
      expect(response).to have_http_status(:too_many_requests)
      travel 2.seconds
      attempt(password: 'test-password')
      expect(response).to redirect_to(root_path)
    end
  end

  it 'uses separate counters for different IPs and the same counter for different emails' do
    10.times { attempt }
    attempt(ip: '198.51.100.11', password: 'test-password')
    expect(response).to redirect_to(root_path)
    post login_path, params: { session: { email: 'unknown@example.test', password: 'incorrect' } }, headers: { 'REMOTE_ADDR' => address }
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'does not throttle the login page, logout or authenticated usage pages' do
    attempt(password: 'test-password')
    9.times { attempt }
    attempt
    expect(response).to have_http_status(:too_many_requests)
    get status_path
    expect(response).to have_http_status(:ok)
    get login_path
    expect(response).to have_http_status(:ok)
    delete logout_path
    expect(response).to redirect_to(login_path)
  end
end
