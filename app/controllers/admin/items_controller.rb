class Admin::ItemsController < ApplicationController
  include AdminOrdering
  helper_method :ordering_model, :ordering_index_path, :ordering_edit_path, :ordering_save_path
  before_action :require_admin

  def index
    @items = Item.in_order
  end

  def show
    @item = Item.find(params[:id])
  end

  def new
    @item = Item.new
  end

  def create
    @item = Item.new(item_params)

    if @item.save
      redirect_to admin_item_path(@item), notice: "利用設定「#{@item.name}」を登録しました。"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @item = Item.find(params[:id])
  end

  def update
    @item = Item.find(params[:id])

    if @item.update(item_params)
      redirect_to admin_item_path(@item), notice: "利用設定「#{@item.name}」を更新しました。"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    item = Item.find(params[:id])
    if item.destroy
      redirect_to admin_items_path, notice: "利用設定「#{item.name}」を削除しました。"
    else
      redirect_to admin_item_path(item), alert: item.errors.full_messages.join(' ')
    end
  end

  private

  def item_params
    params.require(:item).permit(:name, :disabled, :reason_policy, :usage_mode)
  end

  def ordering_model
    Item
  end

  def ordering_index_path
    admin_items_path
  end

  def ordering_edit_path
    reorder_admin_items_path
  end

  def ordering_save_path
    update_order_admin_items_path
  end

  def require_admin
    redirect_to root_path unless current_user.admin?
  end
end
