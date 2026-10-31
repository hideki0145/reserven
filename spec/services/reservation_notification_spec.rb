require 'rails_helper'

RSpec.describe ReservationNotification do
  it 'escapes control characters and bounds long text for grouped and changed-reason notifications' do
    actor = create_user(name: '<!channel>' * 30)
    usage = Usage.new(item_name_snapshot: '&' * 500, user_name_snapshot: actor.name,
                      starts_at: Time.current, ends_at: 1.hour.from_now, reason: '&' * 500)
    notification = described_class.build(event: :create, usages: Array.new(25, usage), actor: actor)
    expect(notification[:blocks].all? { |block| block[:text][:text].length <= 3000 }).to be(true)
    expect(notification[:blocks].map { |block| block[:text][:text] }.join).not_to include('<!channel>')
    changed = described_class.build(event: :update, usages: [usage], actor: actor,
                                    previous: { 'starts_at' => usage.starts_at, 'ends_at' => usage.ends_at, 'reason' => '<' * 500 })
    expect(changed[:blocks].all? { |block| block[:text][:text].length <= 3000 }).to be(true)
  end
end
