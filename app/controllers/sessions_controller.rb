class SessionsController < ApplicationController
  layout "auth", only: :new

  def new
    redirect_to(Current.host ? host_root_path : root_path) and return if Current.session.present?
  end

  def destroy
    sign_out!
    redirect_to login_path, notice: I18n.t("auth.logout")
  end
end
