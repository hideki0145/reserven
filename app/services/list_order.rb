require 'digest'

class ListOrder
  class Invalid < StandardError; end

  def self.version(records)
    Digest::SHA256.hexdigest(records.map { |record| "#{record.id}:#{record.seq}" }.sort.join(','))
  end

  def self.save!(model, ids, expected_version)
    model.transaction do
      records = model.order(:id).lock.to_a
      unless expected_version.is_a?(String) && expected_version == version(records)
        raise Invalid, '一覧が変更されています。最新の内容で並び替え直してください。'
      end
      ids ||= []
      unless ids.is_a?(Array) && ids.length == records.length &&
             ids.all? { |id| id.is_a?(String) && id.match?(/\A[1-9]\d*\z/) } &&
             ids.map(&:to_i).sort == records.map(&:id).sort
        raise Invalid, '並び順が正しくありません。一覧を読み込み直してください。'
      end
      ids.each_with_index { |id, index| model.where(id: id).update_all(seq: index + 1) }
    end
  end
end
