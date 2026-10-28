class SessionsController < ApplicationController
  skip_before_action :login_required

  def new; end

  def create
    user = User.find_by(email: session_params[:email])

    if user && !user.disabled? && user.authenticate(session_params[:password])
      log_in(user)
      session_params[:remember_cookies] == '1' ? store_remember_cookies(user) : release_remember_cookies(user)
      redirect_to root_path, notice: 'ログインしました。'
    else
      flash.now[:alert] = 'メールアドレスまたはパスワードが正しくありません。'
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    log_out if logged_in?
    redirect_to login_path, notice: 'ログアウトしました。'
  end

  private

  def session_params
    params.require(:session).permit(:email, :password, :remember_cookies)
  end
end
