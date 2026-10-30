require 'rails_helper'

RSpec.describe 'Administrative ordering', type: :request do
  [User, Item].each do |model|
    context "for #{model.name}" do
      let(:admin) { create_user(admin: true) }
      let(:collection) { model == User ? :users : :items }
      let(:edit_path) { public_send("reorder_admin_#{collection}_path") }
      let(:save_path) { public_send("update_order_admin_#{collection}_path") }

      def make_record(model, name)
        model == User ? create_user(name: name) : Item.create!(name: name)
      end

      it 'requires an administrator and rejects missing, duplicate, foreign and stale orders atomically' do
        login(create_user)
        get edit_path
        expect(response).to redirect_to(root_path)
        patch save_path, params: { ids: [] }
        expect(response).to redirect_to(root_path)
        login(admin)
        first = make_record(model, '並び順A')
        last = make_record(model, '並び順B')
        records = model.in_order.to_a
        original = records.map { |r| [r.id, r.seq] }
        version = ListOrder.version(records)
        [[], records.map { first.id.to_s }, records.map(&:id).map(&:to_s) + ['999999']].each do |ids|
          patch save_path, params: { ids: ids, order_version: version }
          expect(model.order(:id).pluck(:id, :seq)).to eq(original.sort)
        end
        first.update_columns(seq: last.seq + 10)
        before = model.order(:id).pluck(:id, :seq)
        patch save_path, params: { ids: records.map(&:id).reverse, order_version: version }
        expect(flash[:alert]).to include('一覧が変更')
        expect(model.order(:id).pluck(:id, :seq)).to eq(before)
      end

      it 'saves the reviewed order including disabled records and appends new records' do
        login(admin)
        first = make_record(model, '並び順A')
        last = make_record(model, '並び順B')
        last.update!(disabled: true)
        records = model.in_order.to_a
        ids = records.map(&:id).reverse
        patch save_path, params: { ids: ids, order_version: ListOrder.version(records) }
        expect(flash[:notice]).to eq('並び順を保存しました。')
        expect(model.in_order.pluck(:id)).to eq(ids)
        added = make_record(model, '末尾')
        expect(model.in_order.last).to eq(added)
        if model == Item
          last.update!(disabled: false)
          get status_path
          expect(Nokogiri::HTML(response.body).css('tbody tr > td:first-child').map(&:text)).to eq(['並び順B', '並び順A', '末尾'])
        end
      end
    end
  end
end
