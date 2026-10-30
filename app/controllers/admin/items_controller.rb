class Admin::ItemsController < ApplicationController
  before_action :require_admin

  def index
    @items = Item.order(:id)
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
      redirect_to admin_item_path(@item), notice: "アイテム「#{@item.name}」を登録しました。"
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
      redirect_to admin_item_path(@item), notice: "アイテム「#{@item.name}」を更新しました。"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    item = Item.find(params[:id])
    if item.destroy
      redirect_to admin_items_path, notice: "アイテム「#{item.name}」を削除しました。"
    else
      redirect_to admin_item_path(item), alert: item.errors.full_messages.join(' ')
    end
  end

  private

  def item_params
    params.require(:item).permit(:name, :disabled, :reason_policy)
  end

  def require_admin
    redirect_to root_path unless current_user.admin?
  end
end
