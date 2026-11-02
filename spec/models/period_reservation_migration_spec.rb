require 'rails_helper'
require Rails.root.join('db/migrate/20261030000003_add_period_reservations')

RSpec.describe AddPeriodReservations do
  it 'preserves legacy rows as immediate usage, supports an empty rollback and guards recorded reservations' do
    stub_const('PeriodReservationDatabase', Class.new(ActiveRecord::Base) { self.abstract_class = true })
    connection = PeriodReservationDatabase.establish_connection(adapter: 'sqlite3', database: ':memory:').lease_connection
    connection.create_table(:users) { |t| t.string :name }
    connection.create_table(:items) { |t| t.string :name }
    connection.create_table(:usages) do |t|
      t.integer :item_id
      t.datetime :starts_at
      t.datetime :ends_at
    end
    connection.execute("INSERT INTO users (id, name) VALUES (1, '利用者A')")
    connection.execute("INSERT INTO items (id, name) VALUES (1, '貸出用端末A')")
    connection.execute("INSERT INTO usages (item_id, starts_at, ends_at) VALUES (1, '2026-10-30 00:00:00', '2026-10-30 01:00:00')")
    migration = described_class.new
    allow(migration).to receive(:connection).and_return(connection)
    migration.up
    expect(connection.select_value('SELECT usage_kind FROM usages')).to eq('immediate')
    expect(connection.select_value('SELECT usage_mode FROM items')).to eq('immediate')
    expect(connection.select_value('SELECT usage_manager FROM users')).to eq(0)
    migration.down
    expect(connection.column_exists?(:usages, :usage_kind)).to be(false)
    expect(connection.select_value('SELECT count(*) FROM usages')).to eq(1)
    migration.up
    connection.execute("UPDATE usages SET usage_kind = 'reservation'")
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(connection.select_value('SELECT usage_kind FROM usages')).to eq('reservation')
  ensure
    PeriodReservationDatabase.remove_connection
  end
end
