class AddUsageReasons < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :reason_policy, :string, default: 'none', null: false
    add_column :usages, :reason, :text
  end
end
