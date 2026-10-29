require 'rails_helper'

RSpec.describe 'Login input preservation', type: :request do
  [false, true].each do |remember|
    it "preserves email and remember=#{remember} on invalid credentials and throttling without echoing the password" do
      email = ' Input@Example.COM '
      password = 'private-password-example'
      11.times do |attempt|
        post login_path, params: { session: { email: email, password: password, remember_cookies: remember ? '1' : '0' } }
        expect(response.status).to eq(attempt == 10 ? 429 : 422)
        html = Nokogiri::HTML(response.body)
        expect(html.at_css('#session_email')['value']).to eq(email)
        expect(html.at_css('#session_remember_cookies').key?('checked')).to eq(remember)
        expect(html.at_css('#session_password')['value']).to be_blank
        expect(response.body).not_to include(password)
      end
      get login_path
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('#session_email')['value']).to be_blank
      expect(html.at_css('#session_remember_cookies').key?('checked')).to be(false)
    end
  end

  it 'escapes the retained email in the input attribute' do
    email = '"><script>alert(1)</script>'
    post login_path, params: { session: { email: email, password: 'incorrect' } }
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('#session_email')['value']).to eq(email)
    expect(response.body).not_to include('<script>alert(1)</script>')
  end
end
