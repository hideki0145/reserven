class ReservationNotification
  TITLES = { create: '予約を登録しました', start: '今すぐ利用の予約を登録しました',
             update: '予約を変更しました', cancel: '予約を取り消しました', finish: '予約の利用を終了しました' }.freeze

  def self.build(event:, usages:, actor:, previous: nil)
    usage = usages.first
    names = usages.first(20).map { |row| "・#{row.item_name_snapshot.truncate(80)}" }
    names << "ほか#{usages.length - 20}件(予約一覧で確認できます)" if usages.length > 20
    lines = ["*対象*\n#{escape(names.join("\n")).truncate(1500, omission: '…(予約一覧で確認できます)')}",
             "*利用者*: #{escape(usage.user_name_snapshot.truncate(100))}"]
    if previous
      lines << "*変更前の開始*: #{format_time(previous['starts_at'])}"
      lines << "*変更前の終了*: #{format_time(previous['ends_at'])}"
      lines << "*変更後の開始*: #{format_time(usage.starts_at)}"
      lines << "*変更後の終了*: #{format_time(usage.ends_at)}"
    else
      lines << "*開始日時*: #{format_time(usage.starts_at)}"
      lines << "*終了日時*: #{format_time(usage.ends_at)}"
    end
    lines << "*終了操作*: #{format_time(usage.finished_at)}" if event == :finish
    lines << "*取消操作*: #{format_time(usage.cancelled_at)}" if event == :cancel
    lines << "*#{event == :create || event == :start ? '登録者' : '操作者'}*: #{escape(actor.name.truncate(100))}"
    blocks = [{ type: 'section', text: { type: 'mrkdwn', text: "*#{TITLES.fetch(event)}*", verbatim: true } },
              { type: 'section', text: { type: 'mrkdwn', text: lines.join("\n"), verbatim: true } }]
    if previous && previous['reason'] != usage.reason
      blocks << section("*変更前の利用理由*: #{escape(previous['reason'].presence || '(なし)')}")
      blocks << section("*変更後の利用理由*: #{escape(usage.reason.presence || '(なし)')}")
    elsif usages.any? { |row| row.reason.present? }
      blocks << section("*利用理由*: #{escape(usages.find { |row| row.reason.present? }.reason)}")
    end
    summary_names = escape(usages.map(&:item_name_snapshot).join('、').truncate(200))
    { text: "#{TITLES.fetch(event)}。#{summary_names} / #{usages.length}件 / #{escape(usage.user_name_snapshot.truncate(100))} / #{period(usage.starts_at, usage.ends_at)}", blocks: blocks }
  end

  def self.section(text)
    { type: 'section', text: { type: 'mrkdwn', text: text, verbatim: true } }
  end

  def self.period(from, to)
    "#{format_time(from)} ～ #{format_time(to)}"
  end

  def self.format_time(time)
    I18n.l(time, format: :usage_datetime)
  end

  def self.escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  private_class_method :section, :period, :format_time, :escape
end
