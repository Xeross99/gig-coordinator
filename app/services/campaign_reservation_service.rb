class CampaignReservationService
  WINDOW = Event::RESERVATION_WINDOW

  # Mirror ReservationService.seed_on_create — każdy mistrz_piora dostaje
  # zaproszenie 2.5h do primary rostera kampanii. Pierwszy kto kliknie
  # „Akceptuję" trafia na confirmed, kolejni (po wypełnieniu capacity) na
  # waitlist.
  def self.seed_on_create(campaign)
    with_lock(campaign) do
      invite_candidates(campaign).each { |u| invite!(campaign, u) }
    end
  end

  # Replace one vacated slot in primary roster. Waitlist first → potem
  # następny mistrz spoza kampanii. Zwraca true jeśli coś przesunęliśmy.
  def self.refill_one(campaign)
    with_lock(campaign) do
      next unless promote_from_waitlist(campaign).nil?

      next_candidate = invite_candidates(campaign, limit: 1).first
      invite!(campaign, next_candidate) if next_candidate
    end
  end

  # Capacity wzrosła → wypełnij wolne sloty (waitlist first, potem mistrz).
  def self.fill_open_slots(campaign)
    with_lock(campaign) do
      loop do
        open = campaign.capacity - campaign.campaign_participations.holding_slot.count
        break if open <= 0

        next if promote_from_waitlist(campaign)

        candidate = invite_candidates(campaign, limit: 1).first
        break unless candidate
        invite!(campaign, candidate)
      end
    end
  end

  # Capacity spadła → degraduj najświeższych confirmed na początek waitlisty.
  def self.demote_overflow(campaign)
    with_lock(campaign) do
      overflow = campaign.campaign_participations.confirmed.count - campaign.capacity
      next if overflow <= 0

      to_demote = campaign.campaign_participations.confirmed.order(position: :desc).limit(overflow).to_a
      campaign.campaign_participations.waitlist.update_all(Arel.sql("position = position + #{overflow.to_i}"))

      to_demote.sort_by(&:position).each_with_index do |p, idx|
        p.update!(status: :waitlist, position: idx + 1)
      end
      CampaignParticipation.resequence!(campaign, :confirmed)
    end
  end

  # Cancel jednej wygasłej rezerwacji. Wołany przez per-rezerwacyjny
  # ReservationExpirationJob zaplanowany na `reserved_until`. Idempotentny —
  # jeśli mistrz w międzyczasie zaakceptował/odrzucił, nic się nie dzieje.
  # Refill slotu robi CampaignParticipation#cascade_cancellation
  # (reserved→cancelled ⇒ refill_one).
  def self.expire_one!(campaign_participation)
    campaign = campaign_participation.event_campaign
    with_lock(campaign) do
      fresh = campaign.campaign_participations.find_by(id: campaign_participation.id)
      next unless fresh&.reserved?
      next unless fresh.reserved_until.present? && fresh.reserved_until <= Time.current

      fresh.cancellation_reason = :expired
      fresh.update!(status: :cancelled, reserved_until: nil)
    end
  end

  # Safety-net sweep — już NIE schedulowany (każda rezerwacja ma własny job
  # wygaśnięcia). Zostaje do ręcznego użycia z konsoli.
  def self.expire_stale!
    CampaignParticipation.reserved.where("reserved_until <= ?", Time.current)
                         .includes(:event_campaign).find_each { |cp| expire_one!(cp) }
  end

  # --- internals ---

  # Top-tier-only: tylko mistrz_piora, brak cascade w dół. Wykluczamy już
  # uczestniczących + zablokowanych u tego hosta (defense-in-depth — invariant
  # mówi że mistrz nigdy nie ma blokady, ale liczy się zachowanie pod każdą
  # zmianą).
  def self.invite_candidates(campaign, limit: nil)
    blocked_ids = HostBlock.where(host_id: campaign.host_id).pluck(:user_id)
    scope = User.enabled.mistrz_piora
                .where.not(id: campaign.campaign_participations.pluck(:user_id) + blocked_ids)
                .order(:id)
    limit ? scope.limit(limit) : scope
  end

  def self.invite!(campaign, user)
    pos = (campaign.campaign_participations.reserved.maximum(:position) || 0) + 1
    campaign.campaign_participations.create!(
      user: user, status: :reserved, position: pos,
      reserved_until: Time.current + WINDOW
    )
    WebPushNotifier.perform_later(:campaign_invitation,
                                  event_campaign_id: campaign.id, user_id: user.id)
  end

  def self.promote_from_waitlist(campaign)
    promoted = campaign.campaign_participations.waitlist.order(:position).first
    return nil unless promoted

    pos = (campaign.campaign_participations.confirmed.maximum(:position) || 0) + 1
    promoted.update!(status: :confirmed, position: pos)
    CampaignParticipation.resequence!(campaign, :waitlist)
    WebPushNotifier.perform_later(:campaign_promotion, campaign_participation_id: promoted.id)
    promoted
  end

  def self.with_lock(campaign, &block)
    EventCampaign.transaction do
      campaign.lock!
      block.call
    end
  end
end
