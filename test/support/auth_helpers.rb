module AuthHelpers
  def sign_in_as(record)
    token = record.signed_id(purpose: :magic_link, expires_in: 15.minutes)
    get verify_magic_link_path(token: token)
  end
end
