class Admin::UsersController < ApplicationController
  before_action :require_admin

  def index
    @users = User.order(:id)
  end

  def show
    @user = User.find(params[:id])
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to admin_user_path(@user), notice: "ユーザ「#{@user.name}」を登録しました。"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])

    if @user.update(user_params)
      notice = "ユーザ「#{@user.name}」を更新しました。"
      if @user.id == current_user.id && @user.disabled?
        log_out
        redirect_to login_path, notice: notice
      else
        redirect_to @user.id == current_user.id && !@user.admin? ? root_path : admin_user_path(@user), notice: notice
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    user = User.find(params[:id])
    if user.destroy
      redirect_to admin_users_path, notice: "ユーザ「#{user.name}」を削除しました。"
    else
      redirect_to admin_user_path(user), alert: user.errors.full_messages.join(' ')
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :admin, :disabled, :password, :password_confirmation)
  end

  def require_admin
    redirect_to root_path unless current_user.admin?
  end
end
