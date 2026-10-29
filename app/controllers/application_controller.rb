class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user
  before_action :login_required

  private

  def log_in(user)
    reset_session
    session[:user_id] = user.id
  end

  def log_out
    release_remember_cookies(current_user)
    reset_session
    @current_user = nil
  end

  def store_remember_cookies(user)
    user.create_remember_digest
    cookie_options = { httponly: true, same_site: :lax, secure: Rails.env.production? }
    cookies.permanent.signed[:user_id] = cookie_options.merge(value: user.id)
    cookies.permanent[:remember_token] = cookie_options.merge(value: user.remember_token)
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
      if @current_user && @current_user.disabled?
        reset_session
        cookies.delete(:user_id)
        cookies.delete(:remember_token)
        @current_user = nil
      end
      @current_user
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
