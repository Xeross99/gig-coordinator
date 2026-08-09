class SwapExpirationJob < ApplicationJob
  queue_as :default

  # Schedulowany przy tworzeniu propozycji wymiany (SwapProposal after_create)
  # z `wait_until: expires_at`. Idempotentny — jeśli propozycja została już
  # zaakceptowana/odrzucona (albo ktoś przesunął expires_at), nic nie robi.
  def perform(swap_proposal_id:)
    proposal = SwapProposal.find_by(id: swap_proposal_id)
    return unless proposal&.pending?
    return unless proposal.time_expired?

    proposal.update!(status: :expired)
  end
end
