class ApplicationController < ActionController::Base
  helper_method :current_user
  before_action :login_required

  private

  def log_in(user)
    session[:user_id] = user.id
  end

  def log_out
    release_remember_cookies(current_user)
    reset_session
    @current_user = nil
  end

  def store_remember_cookies(user)
    user.create_remember_digest
    cookies.permanent.signed[:user_id] = user.id
    cookies.permanent[:remember_token] = user.remember_token
  end

  def release_remember_cookies(user)
    user.delete_remember_digest
    cookies.delete(:user_id)
    cookies.delete(:remember_token)
  end

  def logged_in?
    !current_user.nil?
  end

  def current_user
    if (user_id = session[:user_id])
      @current_user ||= User.find_by(id: user_id)
    elsif (user_id = cookies.signed[:user_id])
      user = User.find_by(id: user_id)
      if user&.authenticated?(cookies[:remember_token])
        log_in(user)
        @current_user = user
      end
    end
  end

  def login_required
    redirect_to login_path unless logged_in?
  end
end
