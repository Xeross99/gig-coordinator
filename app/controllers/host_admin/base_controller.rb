module HostAdmin
  class BaseController < ApplicationController
    layout "host_admin"

    # Gospodarz nie ma Current.user (Session jest polimorficzna), więc globalny
    # require_user! z ApplicationController zamknąłby mu cały panel.
    skip_before_action :require_user!
    before_action :require_host!

    private

    # Bramka sesji gospodarza. Mieszka tutaj, a nie w ApplicationController,
    # bo panel `/panel/*` jest jedynym miejscem w aplikacji, które jej używa —
    # w odróżnieniu od `require_user!`, wołanego przez kilkanaście kontrolerów
    # workerowych i dlatego trzymanego wyżej.
    def require_host!
      return if Current.host

      redirect_to login_path, alert: "Zaloguj się, aby kontynuować."
    end
  end
end
