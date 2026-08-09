class SessionsController < ApplicationController
  layout "auth", only: :new

  def new
    redirect_to(Current.host ? host_root_path : root_path) and return if Current.session.present?
  end

  def destroy
    sign_out!
    redirect_to login_path, notice: Copy::Auth::LOGOUT
  end

  def destroy_remote
    return redirect_to(login_path, alert: "Zaloguj się, aby kontynuować.") if Current.session.blank?

    target = Current.session.authenticatable.sessions.find_by(id: params[:id])
    return redirect_to(after_remote_destroy_path, alert: "Nie znaleziono sesji.") if target.nil?

    if target.id == Current.session.id
      sign_out!
      redirect_to login_path, notice: Copy::Auth::LOGOUT
    else
      target.destroy
      redirect_to after_remote_destroy_path, notice: "Urządzenie wylogowane."
    end
  end

  private

  def after_remote_destroy_path
    Current.host ? edit_host_profile_path : edit_profile_path
  end
end
