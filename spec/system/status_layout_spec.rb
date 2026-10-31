require 'rails_helper'

RSpec.describe 'Status header and controls', type: :system do
  [1024, 390].each do |width|
    it "aligns the header and usage controls at #{width}px" do
      travel_to(Time.zone.local(2026, 10, 29, 12, 0)) do
        Item.create!(name: '検証用端末A')
        page.current_window.resize_to(width, 900)
        login(create_user)
        expect(page).to have_css('.status-greeting strong', text: 'テスト利用者')
        expect(page).to have_css('.status-header', style: { 'flex-direction' => width >= 768 ? 'row' : 'column' })
        expect(page.evaluate_script("getComputedStyle(document.querySelector('.status-greeting')).fontSize")).to eq('16px')
        expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
        aligned = <<~JS
          (() => {
            const input = document.querySelector('[data-deadline-field] input');
            const button = input.form.querySelector('input[type="submit"]');
            return Math.abs(input.getBoundingClientRect().top - button.getBoundingClientRect().top) < 1;
          })()
        JS
        expect(page.evaluate_script(aligned)).to be(true)
        click_button '利用する'
        expect(page).to have_button('延長する')
        expect(page.evaluate_script(aligned)).to be(true)
        expect(page).to have_content('最終更新: 2026/10/29 12:00')
      end
    end
  end
end
