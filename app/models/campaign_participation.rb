class CampaignParticipation < ApplicationRecord
  belongs_to :event_campaign
  belongs_to :user
  has_many :campaign_participation_events, dependent: :delete_all

  enum :status, { confirmed: 0, waitlist: 1, cancelled: 2, reserved: 3 }

  validates :user_id, uniqueness: { scope: :event_campaign_id }

  scope :active,       -> { where.not(status: :cancelled) }
  scope :holding_slot, -> { where(status: %i[confirmed reserved]) }

  attr_accessor :cancellation_reason, :skip_sub_event_sync

  after_commit :broadcast_campaign_updates,       on: %i[create update destroy]
  after_commit :log_participation_event,          on: %i[create update]
  after_commit :enroll_in_sub_events,             on: %i[create update]
  after_commit :cascade_cancellation,             on: :update
  after_commit :schedule_reservation_expiration,  on: %i[create update]

  def reservation_expired?
    reserved? && reserved_until.present? && reserved_until <= Time.current
  end

  def self.resequence!(campaign, status)
    campaign.campaign_participations.where(status: status).order(:position).each_with_index do |p, i|
      p.update_column(:position, i + 1) if p.position != i + 1
    end
  end

  private

  def broadcast_campaign_updates
    return unless roster_relevant_change?

    fresh_campaign = EventCampaign.find_by(id: event_campaign_id)
    return unless fresh_campaign

    # `_later` — rendery partiali idą z kolejki, nie w wątku requestu
    # (kaskada anulacji kampanii potrafi odpalić ten callback wielokrotnie).
    Turbo::StreamsChannel.broadcast_replace_later_to(
      [ fresh_campaign, :roster ],
      target: ActionView::RecordIdentifier.dom_id(fresh_campaign, :roster),
      partial: "event_campaigns/roster",
      locals: { campaign: fresh_campaign }
    )
    Turbo::StreamsChannel.broadcast_replace_later_to(
      [ fresh_campaign, :counts ],
      target: ActionView::RecordIdentifier.dom_id(fresh_campaign, :counts),
      partial: "event_campaigns/counts",
      locals: { campaign: fresh_campaign }
    )
  end

  def roster_relevant_change?
    return true if destroyed?
    return true if previously_new_record?
    saved_change_to_status? || saved_change_to_position?
  end

  def log_participation_event
    event_type = classify_transition
    return unless event_type

    campaign_participation_events.create!(event_type: event_type)
  end

  def enroll_in_sub_events
    return if destroyed?
    return if skip_sub_event_sync
    return unless confirmed? || waitlist?

    became_active = previously_new_record? ||
      (saved_change_to_status? && saved_change_to_status[0].in?([ "cancelled", "reserved" ]))

    was_promoted = !previously_new_record? &&
      saved_change_to_status? && saved_change_to_status == [ "waitlist", "confirmed" ]

    return unless became_active || was_promoted

    event_campaign.events.where("scheduled_at > ?", Time.current).find_each do |event|
      Event.transaction do
        event.lock!
        existing = event.participations.find_by(user_id: user_id)

        if was_promoted
          next unless existing&.waitlist?
          next if event.full?
          pos = (event.participations.confirmed.maximum(:position) || 0) + 1
          existing.update!(status: :confirmed, position: pos)
        else
          next if existing&.confirmed? || existing&.waitlist?
          # Status na sub-evencie zależy od wolnych slotów sub-eventu, nie od
          # statusu na primary — waitlister kampanii łapie wolne miejsce.
          sub_status = event.full? ? :waitlist : :confirmed
          pos = (event.participations.where(status: sub_status).maximum(:position) || 0) + 1

          if existing
            existing.update!(status: sub_status, position: pos, reserved_until: nil)
          else
            event.participations.create!(user_id: user_id, status: sub_status, position: pos)
          end
        end
      end
    end
  end

  # Mirror of Participation#refill_after_cancellation for the primary roster,
  # plus the sub-event cascade. Fires on ANY transition into :cancelled —
  # controller, API, sweeper or `rails console` — so leaving the campaign
  # always (1) refills the primary slot and (2) removes the user from every
  # upcoming sub-event, promoting sub-event waitlisters into the freed slots.
  #
  # - confirmed → cancelled: promote the oldest primary waitlister. The promote
  #   sets `skip_sub_event_sync` — the promoted person's sub-event slots are
  #   handed over by the cascade below (with campaign-confirmed priority),
  #   1-in-1-out, instead of the generic enroll_in_sub_events.
  # - reserved  → cancelled: refill_one (waitlist first, then invite the next
  #   mistrz_piora). The promoted waitlister enrolls into sub-events via the
  #   normal enroll_in_sub_events path (a reservation held no sub-event slots).
  # - waitlist  → cancelled: just close the position gap.
  def cascade_cancellation
    return if skip_sub_event_sync
    return unless saved_change_to_status? && status == "cancelled"

    campaign = EventCampaign.find_by(id: event_campaign_id)
    return unless campaign

    promoted = nil
    case saved_change_to_status[0]
    when "confirmed"
      EventCampaign.transaction do
        campaign.lock!
        promoted = promote_primary_waitlister(campaign)
        CampaignParticipation.resequence!(campaign, :confirmed)
        CampaignParticipation.resequence!(campaign, :waitlist)
      end
      WebPushNotifier.perform_later(:campaign_promotion, campaign_participation_id: promoted.id) if promoted
    when "reserved"
      CampaignReservationService.refill_one(campaign)
      EventCampaign.transaction do
        campaign.lock!
        CampaignParticipation.resequence!(campaign, :confirmed)
        CampaignParticipation.resequence!(campaign, :waitlist)
      end
    when "waitlist"
      EventCampaign.transaction do
        campaign.lock!
        CampaignParticipation.resequence!(campaign, :waitlist)
      end
    end

    cancel_on_sub_events(campaign, promoted)
  end

  def promote_primary_waitlister(campaign)
    promoted = campaign.campaign_participations.waitlist.order(:position).first
    return nil unless promoted

    pos = (campaign.campaign_participations.confirmed.maximum(:position) || 0) + 1
    promoted.skip_sub_event_sync = true
    promoted.update!(status: :confirmed, position: pos)
    promoted
  end

  def cancel_on_sub_events(campaign, campaign_promoted)
    campaign_confirmed_ids = campaign.campaign_participations.confirmed.pluck(:user_id) if campaign_promoted

    campaign.events.where("scheduled_at > ?", Time.current).find_each do |event|
      Event.transaction do
        event.lock!
        participation = event.participations.active.find_by(user_id: user_id)
        next unless participation

        was_confirmed = participation.confirmed?
        # The vacated sub-event slot is filled HERE with campaign-confirmed
        # priority — the generic Participation refill must not race us.
        participation.skip_refill = true
        participation.update!(status: :cancelled, reserved_until: nil)

        if was_confirmed
          sub_promoted = campaign_confirmed_ids &&
            event.participations.waitlist.where(user_id: campaign_confirmed_ids).order(:position).first
          sub_promoted ||= event.participations.waitlist.order(:position).first
          if sub_promoted
            pos = (event.participations.confirmed.maximum(:position) || 0) + 1
            sub_promoted.update!(status: :confirmed, position: pos)
            PromotionMailer.with(participation: sub_promoted).notify.deliver_later
            WebPushNotifier.perform_later(:promotion, participation_id: sub_promoted.id)
          end
        end
        Participation.resequence!(event, :confirmed)
        Participation.resequence!(event, :waitlist)
      end
    end
  end

  # Mirror of Participation#schedule_reservation_expiration — one job per
  # reservation, fired exactly at reserved_until. Console-safe, idempotent.
  def schedule_reservation_expiration
    return unless reserved? && reserved_until.present?
    return unless previously_new_record? || saved_change_to_reserved_until?

    ReservationExpirationJob.set(wait_until: reserved_until).perform_later(campaign_participation_id: id)
  end

  def classify_transition
    if previously_new_record?
      case status
      when "confirmed" then :joined
      when "waitlist"  then :joined_waitlist
      when "reserved"  then :reserved
      end
    elsif saved_change_to_status?
      prev_status, new_status = saved_change_to_status
      case [ prev_status, new_status ]
      in [ "cancelled", "confirmed" ] then :joined
      in [ "cancelled", "waitlist"  ] then :joined_waitlist
      in [ "waitlist",  "confirmed" ] then :promoted
      in [ "reserved",  "confirmed" ] then :accepted
      in [ "reserved",  "cancelled" ] then cancellation_reason == :expired ? :expired : :declined
      in [ _,           "cancelled" ] then :cancelled
      else nil
      end
    end
  end
end
