require 'rails_helper'

RSpec.describe 'List ordering', type: :request do
  before { login(create_user(admin: true, name: '管理者')) }

  around do |example|
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      # Expose accidental reliance on SQLite's unordered scan order.
      previous = connection.select_value('PRAGMA reverse_unordered_selects')
      begin
        connection.execute('PRAGMA reverse_unordered_selects = ON')
        example.run
      ensure
        connection.execute("PRAGMA reverse_unordered_selects = #{previous}")
      end
    end
  end

  def row_names
    Nokogiri::HTML(response.body).css('tbody tr').map { |row| row.at_css('td').text.strip }
  end

  it 'keeps users in ID order after editing and disabling an account' do
    first = create_user(name: 'Z利用者')
    second = create_user(name: 'A利用者')
    get admin_users_path
    expect(response).to have_http_status(:ok)
    expect(row_names).to eq(['管理者', first.name, second.name])

    patch admin_user_path(first), params: { user: { name: '更新した利用者', disabled: '1' } }
    expect(response).to redirect_to(admin_user_path(first))
    get admin_users_path
    expect(row_names).to eq(['管理者', '更新した利用者', second.name])
  end

  it 'keeps all admin items in ID order after editing and disabling an item' do
    first = Item.create!(name: 'ZのPC')
    second = Item.create!(name: 'AのPC', disabled: true)
    get admin_items_path
    expect(response).to have_http_status(:ok)
    expect(row_names).to eq([first.name, second.name])

    patch admin_item_path(first), params: { item: { name: '更新したPC', disabled: '1' } }
    expect(response).to redirect_to(admin_item_path(first))
    get admin_items_path
    expect(row_names).to eq(['更新したPC', second.name])
  end

  it 'keeps visible status items in item ID order as disabled items disappear and return' do
    first = Item.create!(name: 'ZのPC')
    hidden = Item.create!(name: '未利用の無効PC', disabled: true)
    active = Item.create!(name: '利用中の無効PC', disabled: true)
    last = Item.create!(name: 'AのPC')
    owner = create_user
    create_usage(item: last, user: owner, active: true, expires_at: 1.hour.from_now)
    create_usage(item: active, user: owner, active: true, expires_at: 1.hour.from_now)

    get status_path
    expect(response).to have_http_status(:ok)
    expect(row_names).to eq([first.name, active.name, last.name])
    patch admin_item_path(first), params: { item: { name: '更新したPC', disabled: '1' } }
    expect(response).to redirect_to(admin_item_path(first))
    get status_path
    expect(row_names).to eq([active.name, last.name])

    patch admin_item_path(first), params: { item: { disabled: '0' } }
    expect(response).to redirect_to(admin_item_path(first))
    get status_path
    expect(row_names).to eq(['更新したPC', active.name, last.name])
    expect(row_names).not_to include(hidden.name)
  end
end
