class CampaignSubEventSeeder
  # Sub-event dorzucony do istniejącej serii dziedziczy jej primary roster.
  # Kolejność pierwszeństwa: primary confirmed (po position), potem waitlisterzy
  # kampanii — ci też łapią wolne sloty sub-eventu, ale nigdy przed confirmed.
  # Ile wejdzie na confirmed, decyduje capacity sub-eventu (może być inne niż
  # capacity kampanii); reszta ląduje na jego waitliście.
  def self.call(event)
    return unless event.event_campaign_id?

    campaign = event.event_campaign
    primary  = campaign.campaign_participations
    candidates = primary.confirmed.order(:position).pluck(:user_id) +
                 primary.waitlist.order(:position).pluck(:user_id)
    return if candidates.empty?

    blocked_ids = HostBlock.where(host_id: event.host_id).pluck(:user_id).to_set

    Event.transaction do
      event.lock!
      taken_ids = event.participations.pluck(:user_id).to_set
      ordered   = candidates.reject { |id| taken_ids.include?(id) || blocked_ids.include?(id) }

      # Rezerwacje kampanii wciąż czekają na odpowiedź, więc trzymają slot.
      pending_reservations = primary.reserved.count
      open_slots = [ event.capacity - event.participations.holding_slot.count - pending_reservations, 0 ].max

      seed(event, :confirmed, ordered.first(open_slots))
      seed(event, :waitlist,  ordered.drop(open_slots))
    end
  end

  # Dopisuje userów na koniec kolejki danego statusu, zachowując przekazaną kolejność.
  def self.seed(event, status, user_ids)
    return if user_ids.empty?

    next_position = (event.participations.where(status: status).maximum(:position) || 0) + 1
    user_ids.each_with_index do |user_id, idx|
      event.participations.create!(user_id: user_id, status: status, position: next_position + idx)
    end
  end
  private_class_method :seed
end
