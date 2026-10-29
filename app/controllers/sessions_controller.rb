class SessionsController < ApplicationController
  skip_before_action :login_required
  before_action :retain_login_input, only: :create

  LOGIN_RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new
  rate_limit to: 10, within: 3.minutes, only: :create,
             store: LOGIN_RATE_LIMIT_STORE, with: :login_rate_limit_exceeded

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

  def retain_login_input
    input = params[:session]
    return unless input.is_a?(ActionController::Parameters)

    @login_email = input[:email] if input[:email].is_a?(String)
    @remember_login = input[:remember_cookies] == '1'
  end

  def login_rate_limit_exceeded
    response.set_header('Retry-After', '180')
    flash.now[:alert] = 'ログインの試行回数が上限に達しました。3分ほど待ってから再試行してください。'
    render :new, status: :too_many_requests
  end

  def session_params
    params.require(:session).permit(:email, :password, :remember_cookies)
  end
end
