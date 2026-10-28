# Rate limit counters belong to one example; the application cache is otherwise unchanged.
RSpec.configure do |config|
  config.before do
    SessionsController::LOGIN_RATE_LIMIT_STORE.clear
  end
end
