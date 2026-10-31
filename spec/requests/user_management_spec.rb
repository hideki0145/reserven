require 'rails_helper'

RSpec.describe 'User account management', type: :request do
  let!(:admin) { create_user(admin: true) }
  before { login(admin) }

  it 'normalizes emails when creating and updating users and rejects duplicates' do
    post admin_users_path, params: { user: { name: '新規利用者', email: ' New@Example.COM ',
                                           password: 'test-password', password_confirmation: 'test-password' } }
    created = User.find_by!(email: 'new@example.com')
    expect(response).to redirect_to(admin_user_path(created))
    patch admin_user_path(created), params: { user: { email: ' Updated@Example.COM ' } }
    expect(response).to redirect_to(admin_user_path(created))
    expect(created.reload.email).to eq('updated@example.com')
    patch admin_user_path(created), params: { user: { email: " #{admin.email.upcase} " } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(created.reload.email).to eq('updated@example.com')
  end

  it 'rejects deletion, demotion and disabling of the last active administrator' do
    [{ admin: '0' }, { disabled: '1' }].each do |attributes|
      patch admin_user_path(admin), params: { user: attributes }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('有効な管理者を少なくとも1人残してください。')
      expect(admin.reload).to be_admin
      expect(admin).not_to be_disabled
    end
    expect { delete admin_user_path(admin) }.not_to change(User, :count)
    expect(response).to redirect_to(admin_user_path(admin))
    expect(flash[:alert]).to include('有効な管理者')
  end

  it 'does not count a disabled administrator as a replacement' do
    create_user(admin: true, disabled: true)
    patch admin_user_path(admin), params: { user: { admin: '0' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(admin.reload).to be_admin
  end

  it 'allows demotion, disabling and deletion when another active administrator remains' do
    other = create_user(admin: true)
    patch admin_user_path(other), params: { user: { admin: '0' } }
    expect(other.reload).not_to be_admin
    patch admin_user_path(other), params: { user: { admin: '1', disabled: '1' } }
    expect(other.reload).to be_disabled
    expect { delete admin_user_path(other) }.to change(User, :count).by(-1)
  end

  it 'displays formatted timestamps, centered admin marks and a back button' do
    admin.update!(created_at: Time.zone.local(2026, 10, 28, 19, 30, 15))
    get admin_users_path
    html = Nokogiri::HTML(response.body)
    expect(html.text).to include('2026/10/28 19:30')
    expect(html.text).not_to include('19:30:15')
    row = html.at_css("a[href='#{admin_user_path(admin)}']").ancestors('tr').first
    expect(row.at_css('td.text-center').text).to eq('○')
    get admin_user_path(admin)
    expect(Nokogiri::HTML(response.body).at_css('a.btn.btn-outline-secondary')['href']).to eq(admin_users_path)
  end

  it 'preserves usage when disabling an account and allows reactivation' do
    other = create_user
    item = Item.create!(name: '貸出PC')
    status = create_usage(item: item, user: other, active: true, expires_at: 1.hour.from_now)
    patch admin_user_path(other), params: { user: { disabled: '1' } }
    expect(other.reload).to be_disabled
    expect(status.reload.unfinished?).to be(true)
    patch admin_user_path(other), params: { user: { disabled: '0' } }
    expect(other.reload).not_to be_disabled
  end

  [false, true].each do |disabled|
    it "rejects deletion of an account with overdue usage even when disabled is #{disabled}" do
      other = create_user(disabled: disabled)
      item = Item.create!(name: '利用中の停止PC', disabled: true)
      status = create_usage(item: item, user: other, active: true, expires_at: 1.hour.ago)

      expect { delete admin_user_path(other) }.not_to change(User, :count)
      expect(response).to redirect_to(admin_user_path(other))
      follow_redirect!
      expect(response.body).to include('利用終了していない対象があるため削除できません。')
      expect(status.reload.unfinished?).to be(true)
      expect(status.user_id).to eq(other.id)
      get status_path
      expect(response.body).to include(item.name, other.name, '利用停止中')
    end
  end

  it 'allows deletion after the owner ends all outstanding usage' do
    other = create_user
    item = Item.create!(name: '返却対象PC')
    status = create_usage(item: item, user: other, active: true, expires_at: 1.hour.ago)
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.post login_path, params: { session: { email: other.email, password: 'test-password' } }
    client.post end_use_status_path(item)
    expect(client.response.location).to eq("http://www.example.com#{status_path}")
    expect(status.reload.unfinished?).to be(false)

    expect { delete admin_user_path(other) }.to change(User, :count).by(-1)
    expect(response).to redirect_to(admin_users_path)
    expect(Usage.find(status.id).user_id).to be_nil
    expect(Item.exists?(item.id)).to be(true)
  end

  it 'blocks an already logged-in account on its next request while disabled' do
    other = create_user
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.post login_path, params: { session: { email: other.email, password: 'test-password' } }
    patch admin_user_path(other), params: { user: { disabled: '1' } }
    client.get status_path
    expect(client.response.location).to eq('http://www.example.com/login')
  end

  it 'rejects disabled logins and revokes persistent cookies, while allowing existing sessions after reactivation' do
    other = create_user
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.post login_path, params: { session: { email: other.email, password: 'test-password', remember_cookies: '1' } }
    persistent = %w[user_id remember_token].map { |key| "#{key}=#{client.cookies[key]}" }.join('; ')
    patch admin_user_path(other), params: { user: { disabled: '1' } }
    expect(other.reload.remember_digest).to be_nil
    attempt = ActionDispatch::Integration::Session.new(Rails.application)
    attempt.post login_path, params: { session: { email: other.email, password: 'test-password' } }
    expect(attempt.response.status).to eq(422)
    # Re-enable before the old session makes its next authenticated request.
    patch admin_user_path(other), params: { user: { disabled: '0' } }
    client.get status_path
    expect(client.response.status).to eq(200)
    restored = ActionDispatch::Integration::Session.new(Rails.application)
    restored.get status_path, headers: { 'HTTP_COOKIE' => persistent }
    expect(restored.response.location).to eq('http://www.example.com/login')
    client.post login_path, params: { session: { email: other.email, password: 'test-password' } }
    expect(client.response.location).to eq('http://www.example.com/')
  end
end
