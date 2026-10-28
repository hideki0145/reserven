# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Playwright: Dependencies", "npm ci"
  step "Playwright: Chromium", "bin/playwright install chromium"
  step "Test: RSpec", "bundle exec rspec"
  step "Check: Autoloading", "bin/rails zeitwerk:check"
  step "Build: Assets", "env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile"



  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
