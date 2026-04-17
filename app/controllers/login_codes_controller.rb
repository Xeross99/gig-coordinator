class LoginCodesController < ApplicationController
  layout "auth", only: :new

  def create
    email = normalize_email(params.dig(:login_code, :email))
    record = find_record(email)
    if record
      code = LoginCode.generate_for(record, request: request)
      LoginCodeMailer.with(record: record, code: code.code).notify.deliver_later
      log_dev_code(record, code.code)
    end
    session[:pending_login_email] = email.presence
    redirect_to verify_login_path, notice: I18n.t("auth.code_sent")
  end

  def new
    @email = session[:pending_login_email]
    redirect_to(login_path) and return if @email.blank?
  end

  def verify
    email = session[:pending_login_email].to_s
    record = find_record(email)
    submitted = params[:code].to_s.gsub(/\D/, "")

    if record && (match = LoginCode.consume(record, submitted))
      sign_in!(record)
      session.delete(:pending_login_email)
      redirect_to(record.is_a?(Host) ? host_root_path : root_path) and return
    end

    # Still bump attempts for ghost record? consume already handles for the matched record;
    # for an unknown email we have no record to bump. Same neutral error either way.
    @email = email
    flash.now[:alert] = I18n.t("auth.invalid_code")
    render :new, status: :unprocessable_entity
  end

  private

  def normalize_email(raw)
    raw.to_s.strip.downcase
  end

  def find_record(email)
    return nil if email.blank?
    Host.find_by(email: email) || User.find_by(email: email)
  end

  def log_dev_code(record, code)
    return unless Rails.env.development?
    puts "\n[login-code] #{record.class.name} #{record.email}\n[login-code] kod: #{code}\n\n"
  end
end
