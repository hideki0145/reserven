require 'rails_helper'

RSpec.describe 'Item availability management', type: :request do
  let!(:user) { create_user(admin: true) }
  let!(:item) { Item.create!(name: '停止対象PC', disabled: true) }
  before { login(user) }

  def use_item(owner: user, expires_at: 30.minutes.from_now)
    create_usage(item: item, user: owner, active: true, expires_at: expires_at)
  end

  it 'hides unused disabled items but keeps them in the admin listing' do
    get status_path
    expect(response.body).not_to include(item.name)
    expect(response.body).to include('現在、表示できるアイテムはありません。')
    get admin_items_path
    expect(response.body).to include(item.name, '無効')
    item.update!(disabled: false)
    get status_path
    expect(response.body).to include(item.name, '利用する')
    expect(response.body).not_to include('現在、表示できるアイテムはありません。')
  end

  it 'preserves outstanding usage even after expiry, for both owner and other users' do
    use_item(expires_at: 30.minutes.ago)
    get status_path
    expect(response.body).to include(item.name, '利用停止中', '利用終了')
    expect(response.body).not_to include('延長する', 'value="利用する"')
    expect(response.body).not_to include('期限切れ', '他の利用者は利用を開始できます。')
    login(create_user)
    get status_path
    expect(response.body).to include(item.name, '利用停止中', user.name)
    expect(response.body).not_to include('利用終了', '延長する', 'value="利用する"')
  end

  it 'rejects direct start and extension requests without changing usage or notifying Slack' do
    expect { post update_status_path(item), params: { expires_at: 1.hour.from_now.iso8601 } }.not_to change(Usage, :count)
    expect(flash[:alert]).to include('利用停止中')
    status = use_item
    original = status.ends_at
    post extend_status_path(item), params: { expires_at: 1.hour.from_now.iso8601 }
    expect(status.reload.ends_at).to eq(original)
    expect(flash[:alert]).to include('利用停止中')
    expect(WebMock).not_to have_requested(:post, /hooks\.slack\.com/)
  end

  it 'allows only the owner to end disabled usage and then hides the item' do
    status = use_item(owner: create_user)
    post end_use_status_path(item)
    expect(status.reload.unfinished?).to be(true)
    login(status.user)
    post end_use_status_path(item)
    expect(status.reload.unfinished?).to be(false)
    get status_path
    expect(Nokogiri::HTML(response.body).at_css('tbody').text).not_to include(item.name)
  end

  it 'rechecks disabled status after an overnight confirmation' do
    travel_to(Time.zone.local(2026, 10, 28, 23, 55)) do
      item.update!(disabled: false)
      post update_status_path(item), params: { expires_at: '00:10' }
      expect(response.body).to include('日付をまたぐ利用の確認')
      item.update!(disabled: true)
      expect do
        post update_status_path(item), params: { expires_at: '00:10', confirmed_expires_at: Time.zone.local(2026, 10, 29, 0, 10).iso8601 }
      end.not_to change(Usage, :count)
      expect(flash[:alert]).to include('利用停止中')
    end
  end

  it 'rejects deletion of outstanding usage but permits deletion after it ends' do
    status = use_item
    expect { delete admin_item_path(item) }.not_to change(Item, :count)
    expect(flash[:alert]).to include('利用中のアイテムは削除できません。')
    expect(status.reload.unfinished?).to be(true)
    status.finish!(status.user)
    expect { delete admin_item_path(item) }.to change(Item, :count).by(-1)
  end

  it 'updates disabled state through the admin form and formats timestamps' do
    item.update!(created_at: Time.zone.local(2026, 10, 28, 19, 30, 15))
    patch admin_item_path(item), params: { item: { disabled: '0' } }
    expect(item.reload).not_to be_disabled
    get admin_items_path
    expect(response.body).to include('2026/10/28 19:30:15')
    get admin_item_path(item)
    expect(Nokogiri::HTML(response.body).at_css('a.btn.btn-outline-secondary')['href']).to eq(admin_items_path)
  end

  it 'reports stopped status in the end notification instead of availability' do
    payload = SlackUsageNotification.build(event: :end, item: item, user: user)
    expect(payload[:text]).to include('現在は利用停止中です。')
    expect(payload[:blocks][1][:text][:text]).to include('*状態*: 利用停止中')
  end
end
