class AddDisabledToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :disabled, :boolean, null: false, default: false
  end
end
