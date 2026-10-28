require 'rails_helper'

RSpec.describe Item, type: :model do
  it 'requires a name' do
    expect(Item.new(name: '')).not_to be_valid
    expect(Item.new(name: '会議室')).to be_valid
  end

  it 'removes its dependent status when deleted' do
    item = Item.create!(name: '会議室')
    Status.create!(item: item, user: create_user, expires_at: 1.hour.from_now)
    expect { item.destroy! }.to change(Status, :count).by(-1)
  end
end
