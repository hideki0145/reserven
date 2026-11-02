class AddPeriodReservations < ActiveRecord::Migration[8.1]
  def up
    add_column :items, :usage_mode, :string, default: 'immediate', null: false
    add_column :users, :usage_manager, :boolean, default: false, null: false
    add_column :usages, :usage_kind, :string, default: 'immediate', null: false
    add_column :usages, :reason_policy_snapshot, :string
    add_column :usages, :cancelled_at, :datetime
    add_reference :usages, :cancelled_by, foreign_key: { to_table: :users }
    add_column :usages, :cancelled_by_name_snapshot, :string
    add_index :usages, [:item_id, :usage_kind, :starts_at, :ends_at], name: 'index_usages_on_reservation_period'
    add_index :usages, [:usage_kind, :ends_at]
  end

  def down
    if connection.select_value("SELECT COUNT(*) FROM usages WHERE usage_kind = 'reservation'").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, '期間予約データがあるため戻せません。切替前のバックアップを確認してください。'
    end

    remove_index :usages, name: 'index_usages_on_reservation_period'
    remove_index :usages, [:usage_kind, :ends_at]
    remove_reference :usages, :cancelled_by, foreign_key: { to_table: :users }
    remove_column :usages, :cancelled_by_name_snapshot
    remove_column :usages, :cancelled_at
    remove_column :usages, :reason_policy_snapshot
    remove_column :usages, :usage_kind
    remove_column :users, :usage_manager
    remove_column :items, :usage_mode
  end
end
