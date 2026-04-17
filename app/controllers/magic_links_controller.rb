class MagicLinksController < ApplicationController
  def create
    email = params.dig(:magic_link, :email).to_s.strip.downcase
    record = Host.find_by(email: email) || User.find_by(email: email)
    if record
      token = record.signed_id(purpose: :magic_link, expires_in: 15.minutes)
      MagicLinkMailer.with(record: record, token: token).link.deliver_later
      log_dev_link(record, token)
    end
    redirect_to login_path, notice: I18n.t("auth.check_email")
  end

  # GET /login/verify?token=...
  def show
    token = params[:token]
    record = find_signed_record(token)
    if record
      sign_in!(record)
      redirect_to(record.is_a?(Host) ? host_root_path : root_path)
    else
      redirect_to login_path, alert: I18n.t("auth.invalid_token")
    end
  end

  private

  def find_signed_record(token)
    return nil if token.blank?
    Host.find_signed(token, purpose: :magic_link) ||
      User.find_signed(token, purpose: :magic_link)
  end

  def log_dev_link(record, token)
    return unless Rails.env.development?
    url = verify_magic_link_url(token: token)
    puts "\n[magic-link] #{record.class.name} #{record.email}\n[magic-link] #{url}\n\n"
  end
end
