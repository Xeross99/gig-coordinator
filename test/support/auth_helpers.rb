module AuthHelpers
  # Integration/controller tests: drive the actual login flow — POST email to get
  # a LoginCode, then POST that code to /logowanie/weryfikacja. Cookie lands in
  # the integration session. Two requests, but realistic and exercises the flow.
  def sign_in_as(record)
    post login_codes_path, params: { login_code: { email: record.email } }
    code = LoginCode.where(
      authenticatable_type: record.class.polymorphic_name,
      authenticatable_id:   record.id
    ).order(created_at: :desc).first
    post verify_login_path, params: { code: code.code }
    record
  end
end

# System tests (Capybara/Selenium) walk through the UI: submit email, read the
# freshly-generated LoginCode, fill the 5 digit inputs, submit.
module SystemAuthHelpers
  def sign_in_as(record)
    visit login_path
    fill_in "login_code[email]", with: record.email
    click_on I18n.t("auth.send_code")

    assert_current_path verify_login_path, wait: 5

    code = LoginCode.where(
      authenticatable_type: record.class.polymorphic_name,
      authenticatable_id:   record.id
    ).order(created_at: :desc).first
    raise "No LoginCode generated for #{record.email}" unless code

    # Re-find each iteration — the Stimulus controller mutates state on every
    # keystroke and auto-submits when complete, which can stale-out a cached list.
    code.code.chars.each_with_index do |digit, i|
      all("input[data-code-input-target='digit']", count: 5)[i].send_keys(digit)
    end
  end
end
