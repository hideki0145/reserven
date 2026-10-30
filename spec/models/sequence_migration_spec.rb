require 'rails_helper'
require Rails.root.join('db/migrate/20261030000002_add_seq_to_users_and_items')

RSpec.describe AddSeqToUsersAndItems do
  it 'initializes existing records in ID order without changing their names or disabled flags' do
    stub_const('SequenceMigrationDatabase', Class.new(ActiveRecord::Base) { self.abstract_class = true })
    connection = SequenceMigrationDatabase.establish_connection(adapter: 'sqlite3', database: ':memory:').lease_connection
    [:users, :items].each do |table|
      connection.create_table(table) { |t| t.string :name; t.boolean :disabled }
      connection.execute("INSERT INTO #{table} (id, name, disabled) VALUES (10, '後', 1), (2, '先', 0)")
    end
    migration = described_class.new
    allow(migration).to receive(:connection).and_return(connection)
    migration.up
    [:users, :items].each do |table|
      expect(connection.select_rows("SELECT id, name, disabled, seq FROM #{table} ORDER BY seq")).to eq([[2, '先', 0, 1], [10, '後', 1, 2]])
    end
  ensure
    SequenceMigrationDatabase.remove_connection
  end
end
