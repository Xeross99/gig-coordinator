class ApplicationController < ActionController::Base
  include TracksLastSeen

  allow_browser versions: :modern

  before_action :load_current_session
  before_action :touch_last_seen

  helper_method :admin_signed_in?

  private

  def load_current_session
    token = cookies.signed[:session_token]
    Current.session = token ? Session.find_by(token: token) : nil
  end

  def require_user!
    return if Current.user

    redirect_to login_path, alert: "Zaloguj się, aby kontynuować."
  end

  def admin_signed_in?
    Current.user&.admin?
  end

  def require_admin!
    return if admin_signed_in?

    redirect_to root_path, alert: "Tylko administrator może wykonać tę akcję."
  end

  # Po starcie zlecenia wszystkie mutacje (zapis, anulowanie, kierowca,
  # pasażer, wiadomość) są zablokowane. Wywoływane inline w akcjach kontrolerów —
  # zwraca true gdy redirectuje, false gdy event jest jeszcze otwarty.
  def enforce_event_lock!(event)
    return false unless event.started?

    redirect_to event_path(event), alert: "Zlecenie już się rozpoczęło - zmiany niemożliwe."
    true
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
    Current.session&.destroy
    cookies.delete(:session_token)
    Current.session = nil
  end
end
