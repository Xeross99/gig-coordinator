class ReservationExpirationJob < ApplicationJob
  queue_as :default

  # Per-rezerwacja: schedulowany w momencie utworzenia rezerwacji (callback na
  # Participation / CampaignParticipation) z `wait_until: reserved_until` —
  # zamiast sweepera odpalanego co minutę. Idempotentny: jeśli rezerwacja
  # została w międzyczasie zaakceptowana/odrzucona, expire_one! nic nie robi.
  # Refill zwolnionego slotu dzieje się w callbacku modelu (reserved→cancelled).
  #
  # Wywołany bez argumentów działa jak dawny pełny sweep (Participation +
  # CampaignParticipation + SwapProposal) — safety-net do ręcznego odpalenia
  # z konsoli; nie jest już wpięty w config/recurring.yml.
  def perform(participation_id: nil, campaign_participation_id: nil)
    if participation_id
      participation = Participation.find_by(id: participation_id)
      ReservationService.expire_one!(participation) if participation
    elsif campaign_participation_id
      campaign_participation = CampaignParticipation.find_by(id: campaign_participation_id)
      CampaignReservationService.expire_one!(campaign_participation) if campaign_participation
    else
      ReservationService.expire_stale!
      CampaignReservationService.expire_stale!
      SwapProposal.pending.where("expires_at <= ?", Time.current)
                  .update_all(status: SwapProposal.statuses[:expired])
    end
  end
end
