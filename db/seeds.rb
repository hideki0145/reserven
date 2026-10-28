# Set ADMIN_EMAIL and ADMIN_PASSWORD to create the first administrator.
if ENV['ADMIN_EMAIL'].present? && ENV['ADMIN_PASSWORD'].present?
  user = User.find_or_initialize_by(email: ENV.fetch('ADMIN_EMAIL'))
  if user.new_record?
    user.assign_attributes(name: ENV.fetch('ADMIN_NAME', '管理者'), admin: true,
                           password: ENV.fetch('ADMIN_PASSWORD'),
                           password_confirmation: ENV.fetch('ADMIN_PASSWORD'))
    user.save!
    puts '初期管理者を作成しました。'
  else
    puts '指定したメールアドレスのユーザは既に存在します。変更はありません。'
  end
else
  puts '初期管理者を作成するにはADMIN_EMAILとADMIN_PASSWORDを設定してdb:seedを実行してください。'
end
