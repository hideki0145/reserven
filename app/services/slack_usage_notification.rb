class SlackUsageNotification
  def self.build(event:, item:, user:, expires_at: nil, previous_expires_at: nil, reason: nil)
    case event
    when :start
      title = "🔵 #{item.name} の利用を開始"
      label = '利用期限'
      value = deadline(expires_at)
      text = "#{item.name}を#{user.name}さんが#{value}まで利用します。"
    when :extend
      title = "🕒 #{item.name} の利用を延長"
      label = '利用期限'
      same_day = previous_expires_at.in_time_zone.to_date == expires_at.in_time_zone.to_date
      value = "#{deadline(previous_expires_at)} → #{deadline(expires_at, time_only: same_day)}"
      text = "#{item.name}の利用期限を#{user.name}さんが#{value}に延長しました。"
    when :end
      title = "✅ #{item.name} の利用を終了"
      label = '状態'
      value = item.disabled? ? '利用停止中' : '利用可能'
      text = "#{item.name}を#{user.name}さんが利用終了しました。現在は#{value}です。"
    else
      raise ArgumentError, "Unknown usage event: #{event}"
    end

    lines = ["*利用者*: #{escape(user.name)}"]
    if event == :extend
      lines << "*変更前*: #{deadline(previous_expires_at)}"
      lines << "*利用期限*: #{deadline(expires_at)}"
    else
      lines << "*#{label}*: #{value}"
    end
    if reason.present?
      lines << "*利用理由*: #{escape(reason)}"
      text += " 利用理由: #{escape(reason)}"
    end
    details = { type: 'section', text: { type: 'mrkdwn', text: lines.join("\n"), verbatim: true } }

    {
      text: text,
      blocks: [
        { type: 'section', text: { type: 'mrkdwn', text: emphasize(title), verbatim: true } },
        details
      ]
    }
  end

  def self.deadline(time, time_only: false)
    I18n.l(time.in_time_zone, format: time_only ? '%H:%M' : '%m/%d(%a) %H:%M')
  end

  def self.escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def self.emphasize(title)
    emoji, heading = title.split(' ', 2)
    "#{emoji} *#{escape(heading)}*"
  end

  private_class_method :deadline, :escape, :emphasize
end
