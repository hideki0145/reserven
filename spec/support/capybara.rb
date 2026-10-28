require 'capybara-playwright-driver'

Capybara.default_max_wait_time = 15
Capybara.save_path = Rails.root.join('tmp/capybara', ENV.fetch('TEST_ENV_NUMBER', '').presence || '1')

Capybara.register_driver :customized_playwright do |app|
  Capybara::Playwright::Driver.new(
    app,
    playwright_cli_executable_path: Rails.root.join('bin/playwright').to_s,
    browser_type: :chromium,
    headless: ENV['PLAYWRIGHT_HEADFUL'].blank?,
    viewport: { width: 1440, height: 900 }
  )
end

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :customized_playwright }
end
