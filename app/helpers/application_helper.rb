module ApplicationHelper
  def navigation_link(label, path, controller:)
    active = controller_path == controller
    link_to label, path, class: "nav-link#{' active fw-semibold' if active}",
                        aria: { current: active ? 'page' : nil }
  end

  def usage_period(starts_at, ends_at)
    start = starts_at.in_time_zone
    finish = ends_at.in_time_zone
    end_format = if start.to_date == finish.to_date
      :usage_time
    elsif start.year == finish.year
      :usage_deadline
    else
      :usage_datetime
    end
    "#{l start, format: :usage_datetime} 〜 #{l finish, format: end_format}"
  end
end
