module SwapProposal::Expirable
  extend ActiveSupport::Concern

  EXPIRATION_WINDOW = 1.hour

  included do
    after_create_commit :schedule_expiration_job, if: :expires_at?
  end

  def time_expired?
    expires_at.present? && expires_at <= Time.current
  end

  private

  def schedule_expiration_job
    SwapExpirationJob.set(wait_until: expires_at).perform_later(swap_proposal_id: id)
  end
end
