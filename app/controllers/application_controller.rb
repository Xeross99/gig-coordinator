class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :load_current_session

  helper_method :current_session, :current_user, :current_host, :signed_in?

  private

  def load_current_session
    token = cookies.signed[:session_token]
    Current.session = token ? Session.find_by(token: token) : nil
  end

  def current_session = Current.session
  def current_user    = Current.user
  def current_host    = Current.host
  def signed_in?      = Current.session.present?

  def require_user!
    return if current_user
    redirect_to login_path, alert: I18n.t("auth.login_required")
  end

  def require_host!
    return if current_host
    redirect_to login_path, alert: I18n.t("auth.login_required")
  end

  def sign_in!(authenticatable)
    session_record = authenticatable.sessions.create!(
      user_agent: request.user_agent,
      ip_address: request.remote_ip
    )
    cookies.signed.permanent[:session_token] = { value: session_record.token, httponly: true, same_site: :lax }
    Current.session = session_record
    session_record
  end

  def sign_out!
    current_session&.destroy
    cookies.delete(:session_token)
    Current.session = nil
  end
end
