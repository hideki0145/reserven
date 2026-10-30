module AdminOrdering
  extend ActiveSupport::Concern

  def reorder
    @records = ordering_model.in_order.to_a
    @order_version = ListOrder.version(@records)
    render 'admin/shared/order'
  end

  def update_order
    ListOrder.save!(ordering_model, params[:ids], params[:order_version])
    redirect_to ordering_index_path, notice: '並び順を保存しました。'
  rescue ListOrder::Invalid => e
    redirect_to ordering_edit_path, alert: e.message
  end
end
