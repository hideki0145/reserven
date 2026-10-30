require 'rails_helper'

RSpec.describe 'Usage actors', type: :model do
  it 'preserves the creator and records the actor of each successful update' do
    owner = create_user(name: '利用者A')
    actor = create_user(name: '操作した人')
    usage = Item.create!(name: '貸出用端末A').start_usage!(owner, 1.hour.from_now)
    expect(usage).to have_attributes(created_by: owner, updated_by: owner,
                                    created_by_name_snapshot: owner.name, updated_by_name_snapshot: owner.name)
    usage.extend!(2.hours.from_now, actor)
    expect(usage.reload).to have_attributes(created_by: owner, updated_by: actor, updated_by_name_snapshot: actor.name)
    actor.update!(name: '変更後')
    usage.finish!(actor)
    expect(usage.reload).to have_attributes(updated_by_name_snapshot: '変更後', finished_by_name_snapshot: '変更後')
    actor.destroy!
    expect(usage.reload).to have_attributes(updated_by_id: nil, finished_by_id: nil,
                                           updated_by_name_snapshot: '変更後', created_by: owner)
  end

  it 'leaves a legacy creator unknown and does not change the last actor on failure' do
    user = create_user
    usage = Item.create!(name: '貸出用端末A').start_usage!(user, 1.hour.from_now)
    usage.update_columns(created_by_id: nil, created_by_name_snapshot: nil)
    other = create_user
    expect { usage.extend!(usage.starts_at, other) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(usage.reload.updated_by).to eq(user)
    usage.extend!(2.hours.from_now, other)
    expect(usage.reload.created_by_name_snapshot).to be_nil
    expect(usage.updated_by).to eq(other)
  end
end
