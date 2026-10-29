require 'rails_helper'

RSpec.describe 'Login limit notice', type: :system do
  it 'shows a readable warning without logging the visitor in' do
    user = create_user
    # Fill the real limiter to test its browser response without ten slow UI submissions.
    client = ActionDispatch::Integration::Session.new(Rails.application)
    10.times do
      client.post login_path, params: { session: { email: user.email, password: 'incorrect' } }, headers: { 'REMOTE_ADDR' => '127.0.0.1' }
    end
    visit login_path
    fill_in 'メールアドレス', with: user.email
    fill_in 'パスワード', with: 'test-password'
    click_button 'ログインする'
    expect(page).to have_css('.alert-danger', text: 'ログインの試行回数が上限に達しました。')
    expect(page).to have_button('ログインする')
    visit status_path
    expect(page).to have_current_path(login_path)
  end
end
