class CreateStatuses < ActiveRecord::Migration[6.0]
  def change
    create_table :statuses do |t|
      t.references :item, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :use_flg, default: false, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end
  end
end
