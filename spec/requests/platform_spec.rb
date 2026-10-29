require 'rails_helper'

RSpec.describe 'Rails platform defaults', type: :request do
  it 'serves the standard health check without login' do
    get rails_health_check_path
    expect(response).to have_http_status(:ok)
  end

  it 'shows the standard unsupported-browser page for an old browser' do
    get login_path, headers: {
      'HTTP_USER_AGENT' => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 ' \
                           '(KHTML, like Gecko) Chrome/90.0.4430.72 Safari/537.36'
    }
    expect(response).to have_http_status(:not_acceptable)
    expect(response.body).to include('browser')
  end

  it 'allows a modern browser to open the login form' do
    get login_path, headers: {
      'HTTP_USER_AGENT' => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 ' \
                           '(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36'
    }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('ログインする')
  end

  it 'serves current application JavaScript independently of production asset manifests' do
    get login_path
    source = Nokogiri::HTML(response.body).at_css('script[src]')['src']
    get source
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(Rails.root.join('app/assets/javascripts/application.js').binread)
  end
end
