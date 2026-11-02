require 'rails_helper'

RSpec.describe 'Usage history access', type: :request do
  let(:user) { create_user }
  let(:item) { Item.create!(name: '貸出用端末A') }

  it 'requires login and lets ordinary members filter their own or other members history' do
    get usage_histories_path
    expect(response).to redirect_to(login_path)
    own = create_usage(item: item, user: user, active: false)
    other = create_user(name: '別の利用者')
    create_usage(item: item, user: other, active: false)
    create_usage(item: Item.create!(name: '未終了の端末'), user: user)
    login(user)
    get usage_histories_path(member: 'self')
    expect(response.body).to include('貸出用端末A')
    rows = Nokogiri::HTML(response.body).css('.history-table tbody tr')
    expect(rows.length).to eq(1)
    expect(rows.first.text).to include(own.user_name_snapshot)
    expect(rows.first.text).not_to match(/\d{2}:\d{2}:\d{2}/)
    get usage_histories_path(member: "id:#{other.id}")
    expect(Nokogiri::HTML(response.body).css('.history-table tbody tr').sole.text).to include(other.name)
    expect(response.body).not_to include('<strong>未終了の端末</strong>')
  end

  it 'paginates at the database and keeps filters in page links' do
    26.times { create_usage(item: item, user: user, active: false) }
    login(user)
    get usage_histories_path(target: "id:#{item.id}", member: 'self')
    html = Nokogiri::HTML(response.body)
    expect(html.css('.history-table tbody tr').length).to eq(25)
    next_page = html.at_css('a.btn[href*="page=2"]')['href']
    expect(next_page).to include('member=self', "target=id%3A#{item.id}")
    get next_page
    expect(Nokogiri::HTML(response.body).css('.history-table tbody tr').length).to eq(1)
    get usage_histories_path(page: '-100', target: "id:#{item.id}")
    expect(response.body).to include('1ページ目')
    get usage_histories_path(page: '99999')
    expect(response.body).to include('2ページ目')
  end

  it 'retains and filters deleted names without exposing unsafe markup' do
    item.update!(name: '<script>検証</script>')
    create_usage(item: item, user: user, active: false)
    item.destroy!
    login(user)
    get usage_histories_path(target: 'name:<script>検証</script>')
    expect(response.body).to include('&lt;script&gt;検証&lt;/script&gt;')
    expect(response.body).not_to include('<script>検証</script>')
    expect(Nokogiri::HTML(response.body).css('.history-table tbody tr').length).to eq(1)
  end
end
