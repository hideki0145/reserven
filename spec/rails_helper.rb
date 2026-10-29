ENV['RAILS_ENV'] ||= 'test'
# Tests must not use the developer's Slack credentials.
ENV.delete('SLACK_WEBHOOK_URL')
require_relative '../config/environment'
abort('RSpec cannot run in production') if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'

ActiveRecord::Migration.maintain_test_schema!
WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |file| require file }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include ActiveSupport::Testing::TimeHelpers
  config.include TestRecords
  config.include RequestSpecHelper, type: :request
  config.include SystemSpecHelper, type: :system
  config.example_status_persistence_file_path = 'tmp/rspec/examples.txt'
end
