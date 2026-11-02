require 'rails_helper'

RSpec.describe 'Responsive navigation', type: :system do
  it 'collapses the complete administrator menu below 992px and identifies the current screen' do
    user = create_user(admin: true)
    login(user)
    [390, 768, 820, 991, 992, 1024, 1440].each do |width|
      page.current_window.resize_to(width, 900)
      if width < 992
        expect(page).to have_css('[data-navigation-toggle]')
        expect(page).not_to have_css('#app-navigation')
        find('[data-navigation-toggle]').click
        expect(page).to have_css('#app-navigation a[aria-current="page"]', text: '利用状況')
      else
        expect(page).not_to have_css('[data-navigation-toggle]')
        expect(page).to have_css('#app-navigation a[aria-current="page"]', text: '利用状況')
        expect(page.evaluate_script("new Set(Array.from(document.querySelectorAll('#app-navigation > li')).map(el => el.getBoundingClientRect().top)).size")).to eq(1)
      end
      expect(page.evaluate_script('document.documentElement.scrollWidth <= innerWidth')).to be(true)
      if width < 992
        find('[data-navigation-toggle]').send_keys(:escape)
        expect(page).not_to have_css('#app-navigation')
      end
    end
    click_link '予約一覧'
    click_link '予約する'
    expect(page).to have_css('#app-navigation a.active[aria-current="page"]', text: '予約一覧')
  end
end
