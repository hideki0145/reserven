class StatusesController < ApplicationController
  def home
    @items = Item.all
  end
end
