class MagicLinkMailerPreview < ActionMailer::Preview
  def link
    record = User.first || Host.first
    token  = record.signed_id(purpose: :magic_link, expires_in: 15.minutes)
    MagicLinkMailer.with(record: record, token: token).link
  end
end
