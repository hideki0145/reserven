require 'rails_helper'

RSpec.describe 'Administration', type: :request do
  it 'requires login for both administration areas' do
    [admin_users_path, admin_items_path].each do |path|
      get path
      expect(response).to redirect_to(login_path)
    end
  end

  it 'rejects a non-administrator' do
    login(create_user)
    [admin_users_path, admin_items_path].each do |path|
      get path
      expect(response).to redirect_to(root_path)
    end
    expect { post admin_items_path, params: { item: { name: '拒否' } } }.not_to change(Item, :count)
    expect { post admin_users_path, params: { user: { name: '拒否', email: 'denied@example.com', password: 'test-password' } } }.not_to change(User, :count)
  end

  context 'as an administrator' do
    before { login(create_user(admin: true)) }

    it 'creates, shows, edits and deletes an item' do
      get new_admin_item_path
      expect(response).to have_http_status(:ok)
      expect { post admin_items_path, params: { item: { name: '会議室' } } }.to change(Item, :count).by(1)
      item = Item.last
      get admin_item_path(item)
      expect(response.body).to include('会議室')
      get edit_admin_item_path(item)
      expect(response).to have_http_status(:ok)
      patch admin_item_path(item), params: { item: { name: '会議室2' } }
      expect(item.reload.name).to eq('会議室2')
      get admin_items_path
      expect(response.body).to include('会議室2', 'data-confirm')
      expect { delete admin_item_path(item) }.to change(Item, :count).by(-1)
      get admin_items_path
      expect(response.body).to include('アイテムが登録されていません。')
      get status_path
      expect(response.body).to include('現在、表示できるアイテムはありません。')
    end

    it 'renders item validation errors for creation and update' do
      expect { post admin_items_path, params: { item: { name: '' } } }.not_to change(Item, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('error_explanation')
      item = Item.create!(name: '会議室')
      patch admin_item_path(item), params: { item: { name: '' } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(item.reload.name).to eq('会議室')
    end

    it 'creates, shows, edits and deletes a user' do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
      expect do
        post admin_users_path, params: { user: { name: '追加利用者', email: 'new@example.com', password: 'test-password', password_confirmation: 'test-password' } }
      end.to change(User, :count).by(1)
      user = User.find_by!(email: 'new@example.com')
      get admin_user_path(user)
      expect(response.body).to include('追加利用者')
      get edit_admin_user_path(user)
      expect(response).to have_http_status(:ok)
      patch admin_user_path(user), params: { user: { name: '更新利用者' } }
      expect(user.reload.name).to eq('更新利用者')
      get admin_users_path
      expect(response.body).to include('更新利用者', 'data-confirm')
      expect { delete admin_user_path(user) }.to change(User, :count).by(-1)
    end

    it 'renders user validation errors for creation and update' do
      expect { post admin_users_path, params: { user: { name: '' } } }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      user = create_user
      patch admin_user_path(user), params: { user: { email: '' } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.email).to be_present
    end
  end
end
