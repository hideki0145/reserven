class NormalizeUserEmails < ActiveRecord::Migration[8.1]
  class UserRecord < ActiveRecord::Base
    self.table_name = 'users'
  end

  def up
    users = UserRecord.order(:id).pluck(:id, :email)
    duplicates = users.group_by { |_, email| email.strip.downcase }.values.select { |group| group.size > 1 }
    if duplicates.any?
      ids = duplicates.map { |group| group.map(&:first).join(', ') }.join(' / ')
      raise ActiveRecord::MigrationError,
            "メールアドレスの正規化後に重複するユーザがあります。対象ID: #{ids}。アドレスを修正して再実行してください。"
    end

    users.each do |id, email|
      normalized = email.strip.downcase
      UserRecord.where(id: id).update_all(email: normalized) if normalized != email
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, '正規化前のメールアドレスは復元できません。'
  end
end
