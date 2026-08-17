module HostAdmin
  class BaseController < ApplicationController
    layout "host_admin"

    skip_before_action :require_user!
    before_action :require_host!

    private

    def require_host!
      return if Current.host

      redirect_to login_path, alert: "Zaloguj się, aby kontynuować."
    end
  end
end
