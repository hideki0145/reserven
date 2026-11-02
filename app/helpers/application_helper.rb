module ApplicationHelper
  def navigation_link(label, path, controller:)
    active = controller_path == controller
    link_to label, path, class: "nav-link#{' active fw-semibold' if active}",
                        aria: { current: active ? 'page' : nil }
  end

  def usage_period(starts_at, ends_at)
    UsagePeriod.format(starts_at, ends_at)
  end
end
