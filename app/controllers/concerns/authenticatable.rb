# Cała warstwa sesji: wczytanie zalogowanego z podpisanego ciasteczka, bramki
# dostępu i logowanie/wylogowanie. Session jest polimorficzna (Host albo User),
# więc `Current.session` jest jednym źródłem prawdy, a `Current.user` /
# `Current.host` tylko z niej wynikają.
#
# Domyślnie zamknięte: `require_user!` obowiązuje każdy kontroler dziedziczący
# po ApplicationController, a wyjątki muszą się zadeklarować przez
# `skip_before_action :require_user!` (ekran logowania, panel gospodarza,
# instrukcja instalacji, endpointy fetch dla push).
module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :load_current_session
    before_action :require_user!

    helper_method :admin_signed_in?
  end

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
