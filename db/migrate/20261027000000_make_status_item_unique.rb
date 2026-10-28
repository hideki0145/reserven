class MakeStatusItemUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :statuses, :item_id
    add_index :statuses, :item_id, unique: true
  end
end
