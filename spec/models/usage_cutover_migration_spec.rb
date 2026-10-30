require 'rails_helper'
require Rails.root.join('db/migrate/20261029000001_create_usages')

RSpec.describe CreateUsages do
  it 'discards old usage while preserving users and items, and prevents a lossy rollback' do
    stub_const('UsageCutoverDatabase', Class.new(ActiveRecord::Base) { self.abstract_class = true })
    connection = UsageCutoverDatabase.establish_connection(adapter: 'sqlite3', database: ':memory:').lease_connection
    connection.create_table(:users) { |t| t.string :name }
    connection.create_table(:items) { |t| t.string :name }
    connection.create_table(:statuses) do |t|
      t.references :item, foreign_key: true
      t.references :user, foreign_key: true
      t.boolean :use_flg
    end
    connection.execute("INSERT INTO users (id, name) VALUES (1, '利用者A')")
    connection.execute("INSERT INTO items (id, name) VALUES (1, '貸出用端末A'), (2, '貸出用端末B')")
    connection.execute('INSERT INTO statuses (item_id, user_id, use_flg) VALUES (1, 1, 1), (2, 1, 0)')
    migration = described_class.new
    allow(migration).to receive(:connection).and_return(connection)

    migration.up

    expect(connection.table_exists?(:statuses)).to be(false)
    expect(connection.select_value('SELECT count(*) FROM usages')).to eq(0)
    expect(connection.select_values('SELECT name FROM users')).to eq(['利用者A'])
    expect(connection.select_values('SELECT name FROM items ORDER BY id')).to eq(['貸出用端末A', '貸出用端末B'])
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(connection.table_exists?(:usages)).to be(true)
  ensure
    UsageCutoverDatabase.remove_connection
  end
end
