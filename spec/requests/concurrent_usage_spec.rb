require 'rails_helper'

RSpec.describe 'Concurrent item usage', type: :request do
  # Each request uses a separate connection and must see committed records.
  self.use_transactional_tests = false

  it 'allows only one of two users to start using the same item' do
    users = [create_user, create_user]
    item = Item.create!(name: '同時利用テスト')
    sessions = users.map do |user|
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.post login_path, params: { session: { email: user.email, password: 'test-password' } }
      client
    end
    ready = Queue.new
    start = Queue.new
    workers = sessions.map do |client|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          deadline = 1.hour.from_now.iso8601
          client.post update_status_path(item), params: { expires_at: deadline, confirmed_expires_at: deadline }
          [client.response.status, client.request.flash[:notice]]
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = workers.map(&:value)

    expect(results.map(&:first)).to eq([302, 302])
    expect(results.count { |_, notice| notice.include?('既に利用中') }).to eq(1)
    expect(Status.where(item: item).count).to eq(1)
    expect(users.map(&:id)).to include(item.reload.status.user_id)
  ensure
    workers&.each(&:join)
    item&.reload&.status&.reset
    item&.destroy!
    users&.each(&:destroy!)
  end
end
