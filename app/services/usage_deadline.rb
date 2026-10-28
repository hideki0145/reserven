# Interpret deadlines in Japan time, without guessing dates from malformed input.
class UsageDeadline
  class Invalid < StandardError; end

  def self.parse(value, now: Time.current)
    raise Invalid, '期限を指定してください。' if value.blank?
    raise Invalid, '利用期限を正しい日時で指定してください。' unless value.is_a?(String)

    time_only = /\A(\d{2}):(\d{2})\z/.match(value)
    dated = /\A(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:\d{2})?\z/.match(value)
    raise ArgumentError unless time_only || dated

    date = dated ? Date.iso8601(dated[1]) : now.in_time_zone.to_date
    hour, minute, second = dated ? [dated[2].to_i, dated[3].to_i, dated[4].to_i] : [time_only[1].to_i, time_only[2].to_i, 0]
    raise ArgumentError unless hour.between?(0, 23) && minute.between?(0, 59) && second.between?(0, 59)

    deadline = if dated && dated[5]
      Time.iso8601("#{dated[1]}T#{format('%02d:%02d:%02d', hour, minute, second)}#{dated[5]}").in_time_zone
    else
      Time.zone.local(date.year, date.month, date.day, hour, minute, second)
    end
    if time_only && value == now.in_time_zone.strftime('%H:%M')
      raise Invalid, '現在と同じ時刻は指定できません。'
    end
    deadline += 1.day if time_only && deadline < now
    raise Invalid, '利用期限は現在より後の日時を指定してください。' unless deadline > now

    deadline
  rescue ArgumentError, TypeError
    raise Invalid, '利用期限を正しい日時で指定してください。'
  end
end
