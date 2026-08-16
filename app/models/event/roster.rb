module Event::Roster
  extend ActiveSupport::Concern

  # Read-only view of who is on the event: counts, the preloaded roster payload
  # and membership checks. No writes — every mutation goes through
  # Participation / ReservationService.

  # Single GROUP BY query, memoized per instance. All count helpers below derive
  # from this — so rendering _counts + _roster triggers one query instead of
  # four (confirmed + reserved + waitlist + slots_taken).
  def participation_counts
    @participation_counts ||= participations.group(:status).count.transform_keys(&:to_s)
  end

  def confirmed_count
    participation_counts.fetch("confirmed", 0)
  end

  def reserved_count
    participation_counts.fetch("reserved", 0)
  end

  def waitlist_count
    participation_counts.fetch("waitlist", 0)
  end

  # Slots held against capacity — accepted + awaiting-response both block the slot.
  def slots_taken
    confirmed_count + reserved_count
  end

  def full?
    slots_taken >= capacity
  end

  # Everything the roster partial needs, loaded in a handful of queries and
  # memoized on the instance. Called from the user+host show pages and from
  # Participation#broadcast_event_updates (on a fresh Event instance each
  # broadcast — memoization helps within a single render).
  def roster_data
    @roster_data ||= begin
      all_parts = participations.includes(user: { photo_attachment: :blob }).order(:position).to_a

      by_status = all_parts.group_by(&:status)

      offers   = carpool_offers.includes(carpool_requests: :user).to_a
      offers_by_user = offers.index_by(&:user_id)
      # user_id → CarpoolRequest (theirs as a passenger on this event, if any)
      own_requests = {}
      offers.each do |o|
        o.carpool_requests.each { |r| own_requests[r.user_id] = r }
      end

      pending_swaps = swap_proposals.pending.where("expires_at > ?", Time.current).to_a

      {
        reserved:               by_status["reserved"]  || [],
        confirmed:              by_status["confirmed"] || [],
        waitlist:               by_status["waitlist"]  || [],
        participations_by_user: all_parts.index_by(&:user_id),
        carpool_offers:         offers,
        carpool_offers_by_user: offers_by_user,
        carpool_request_by_user: own_requests,
        swap_proposals_by_target:   pending_swaps.group_by(&:target_id),
        swap_proposals_by_proposer: pending_swaps.group_by(&:proposer_id)
      }
    end
  end

  # True if the given user currently holds an active participation (confirmed
  # / reserved / waitlist) on this event — used to gate carpool UI actions.
  def participant?(user)
    return false if user.blank?

    participations.where(user_id: user.id, status: %i[confirmed reserved waitlist]).exists?
  end
end
