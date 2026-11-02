class SlackUsageNotification
  def self.build(event:, item:, user:, expires_at: nil, previous_expires_at: nil, reason: nil, actor: nil)
    case event
    when :start
      title = "🔵 #{item.name} の利用を開始"
      label = '利用期限'
      value = deadline(expires_at)
      text = "#{item.name}の利用を#{user.name}さんが開始しました。利用期限は#{value}までです。"
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
      lines << "*延長前の利用期限*: #{deadline(previous_expires_at)}"
      lines << "*延長後の利用期限*: #{deadline(expires_at)}"
    else
      lines << "*#{label}*: #{value}"
    end
    if actor && actor.id != user.id
      lines << "*操作者*: #{escape(actor.name)}"
      text += " 操作者: #{escape(actor.name)}"
    end
    blocks = [section(emphasize(title)), section(lines.join("\n"))]
    if event != :end && reason.present?
      blocks << section("*利用理由*: #{escape(reason)}")
      text += " 利用理由: #{escape(reason)}"
    end
    { text: text, blocks: blocks }
  end

  def self.section(text)
    { type: 'section', text: { type: 'mrkdwn', text: text, verbatim: true } }
  end

  def self.deadline(time, time_only: false)
    I18n.l(time.in_time_zone, format: time_only ? '%H:%M' : :usage_deadline)
  end

  def self.escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def self.emphasize(title)
    emoji, heading = title.split(' ', 2)
    "#{emoji} *#{escape(heading)}*"
  end

  private_class_method :deadline, :escape, :emphasize, :section
end
