class UsageHistoriesController < ApplicationController
  def index
    @filters = params.permit(:target, :member).to_h
    history = Usage.where.not(finished_at: nil)
    history = filter(history, :item, @filters['target'])
    member = @filters['member'] == 'self' ? "id:#{current_user.id}" : @filters['member']
    history = filter(history, :user, member)

    @total = history.count
    @pages = [(@total / 25.0).ceil, 1].max
    requested_page = params[:page].is_a?(String) ? Integer(params[:page], exception: false) : nil
    @page = [[requested_page || 1, 1].max, @pages].min
    @usages = history.order(finished_at: :desc, id: :desc).limit(25).offset((@page - 1) * 25)
    @targets = Item.order(:id).map { |item| [item.name, "id:#{item.id}"] }
    @members = [['自分', 'self']] + User.order(:id).map { |user| [user.name, "id:#{user.id}"] }
    @targets += deleted_options(:item)
    @members += deleted_options(:user)
  end

  private

  def filter(history, association, value)
    return history if value.blank?

    kind, identifier = value.split(':', 2)
    case kind
    when 'id'
      history.where("#{association}_id" => identifier)
    when 'name'
      history.where("#{association}_id" => nil, "#{association}_name_snapshot" => identifier)
    else
      history.none
    end
  end

  def deleted_options(association)
    Usage.where("#{association}_id" => nil).where.not(finished_at: nil)
         .distinct.order("#{association}_name_snapshot").pluck("#{association}_name_snapshot")
         .map { |name| ["#{name} (削除済み)", "name:#{name}"] }
  end
end
