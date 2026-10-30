class AddActorsToUsages < ActiveRecord::Migration[8.1]
  def change
    add_reference :usages, :created_by, foreign_key: { to_table: :users }
    add_column :usages, :created_by_name_snapshot, :string
    add_reference :usages, :updated_by, foreign_key: { to_table: :users }
    add_column :usages, :updated_by_name_snapshot, :string
  end
end
