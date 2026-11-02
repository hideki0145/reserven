class UsagePeriod
  def self.format(starts_at, ends_at, separator: '〜')
    start = starts_at.in_time_zone
    finish = ends_at.in_time_zone
    end_format = if start.to_date == finish.to_date
      :usage_time
    elsif start.year == finish.year
      :usage_deadline
    else
      :usage_datetime
    end
    "#{I18n.l(start, format: :usage_datetime)} #{separator} #{I18n.l(finish, format: end_format)}"
  end
end
