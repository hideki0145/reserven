class AddSeqToUsersAndItems < ActiveRecord::Migration[8.1]
  def up
    [:users, :items].each do |table|
      add_column table, :seq, :integer, default: 0, null: false
      add_index table, :seq
      connection.select_values("SELECT id FROM #{table} ORDER BY id").each_with_index do |id, index|
        execute "UPDATE #{table} SET seq = #{index + 1} WHERE id = #{connection.quote(id)}"
      end
    end
  end

  def down
    remove_column :users, :seq
    remove_column :items, :seq
  end
end
