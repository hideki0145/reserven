module UsageListFilters
  extend ActiveSupport::Concern

  private

  def prepare_usage_list_filters(history: false)
    @filters = params.permit(:target, :member, :include_inactive_targets, :include_inactive_members).to_h
    targets = history ? Item.all : Item.where(usage_mode: 'reservation')
    @targets = usage_filter_choices(targets, :item, :target, :include_inactive_targets, history: history)
    @members = [['自分', 'self']] + usage_filter_choices(User.all, :user, :member, :include_inactive_members, history: history)
  end

  def usage_filter_choices(scope, association, selection_key, flag, history:)
    selected = @filters[selection_key].to_s
    inactive_selected = (history && selected.start_with?('name:')) ||
                        (selected.match?(/\A(?:id:)?[1-9]\d*\z/) && scope.klass.where(id: selected.delete_prefix('id:'), disabled: true).exists?)
    if @filters.key?(flag)
      @filters.delete(selection_key) if inactive_selected && @filters[flag] != '1'
    elsif inactive_selected
      # Keep bookmarked filters and links to stopped targets visible in the form.
      @filters[flag] = '1'
    end
    include_inactive = @filters[flag] == '1'
    scope = scope.where(disabled: false) unless include_inactive
    suffix = association == :item ? '利用停止中' : 'アカウント無効'
    choices = scope.reorder(:disabled, :seq, :id).map do |record|
      label = record.disabled? ? "#{record.name}(#{suffix})" : record.name
      [label, history ? "id:#{record.id}" : record.id.to_s]
    end
    if history && include_inactive
      choices += Usage.history_at.where("#{association}_id" => nil)
                      .distinct.order("#{association}_name_snapshot").pluck("#{association}_name_snapshot")
                      .map { |name| ["#{name}(削除済み)", "name:#{name}"] }
    end
    choices
  end
end
