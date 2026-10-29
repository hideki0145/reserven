require 'rails_helper'

RSpec.describe 'Concurrent administrator changes', type: :request do
  self.use_transactional_tests = false

  it 'keeps one active administrator when both are demoted concurrently' do
    admins = [create_user(admin: true), create_user(admin: true)]
    ready = Queue.new
    start = Queue.new
    workers = admins.map do |admin|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user = User.find(admin.id)
          ready << true
          start.pop
          user.update(admin: false)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(workers.map(&:value).sort_by(&:to_s)).to eq([false, true])
    expect(User.active_admins.where(id: admins.map(&:id)).count).to eq(1)
  ensure
    workers&.each(&:join)
    # These committed records belong only to this concurrency example.
    User.where(id: admins&.map(&:id)).delete_all
  end
end
