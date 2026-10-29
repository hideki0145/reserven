class CreateUsages < ActiveRecord::Migration[8.1]
  def up
    create_table :usages do |t|
      t.references :item, foreign_key: true
      t.references :user, foreign_key: true
      t.string :item_name_snapshot, null: false
      t.string :user_name_snapshot, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.datetime :finished_at
      t.string :finish_reason
      t.references :finished_by, foreign_key: { to_table: :users }
      t.string :finished_by_name_snapshot
      t.timestamps
    end
    add_index :usages, [:item_id, :finished_at]
    # Current usage is intentionally not imported at this cutover.
    drop_table :statuses
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          '旧利用状況は復元できません。切替前のバックアップから復元してください。'
  end
end
