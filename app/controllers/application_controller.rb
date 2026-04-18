class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :load_current_session
  before_action :touch_last_seen

  helper_method :current_session, :current_user, :current_host, :signed_in?

  private

  def load_current_session
    token = cookies.signed[:session_token]
    Current.session = token ? Session.find_by(token: token) : nil
  end

  # Stamp the currently signed-in User with `last_seen_at` once per minute so
  # the "online now" indicator + "ostatnio widziany" text in the UI stay fresh
  # without writing to the DB on every request.
  def touch_last_seen
    return unless current_user
    last = current_user.last_seen_at
    return if last && last > 1.minute.ago
    current_user.update_column(:last_seen_at, Time.current)
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
