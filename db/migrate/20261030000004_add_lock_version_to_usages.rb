class AddLockVersionToUsages < ActiveRecord::Migration[8.1]
  def change
    add_column :usages, :lock_version, :integer, default: 0, null: false
  end
end
