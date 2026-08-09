class CampaignSubEventSeeder
  def self.call(event)
    return unless event.event_campaign_id?

    campaign = event.event_campaign
    primary_confirmed = campaign.campaign_participations.confirmed.order(:position).pluck(:user_id)
    primary_waitlist  = campaign.campaign_participations.waitlist.order(:position).pluck(:user_id)
    return if primary_confirmed.empty? && primary_waitlist.empty?

    blocked_ids = HostBlock.where(host_id: event.host_id).pluck(:user_id).to_set

    Event.transaction do
      event.lock!
      existing_user_ids = event.participations.pluck(:user_id).to_set

      confirmed_candidates = primary_confirmed.reject { |id| existing_user_ids.include?(id) || blocked_ids.include?(id) }
      waitlist_candidates  = primary_waitlist.reject { |id| existing_user_ids.include?(id) || blocked_ids.include?(id) }

      pending_reservations = campaign.campaign_participations.reserved.count
      open_slots = [ event.capacity - event.participations.holding_slot.count - pending_reservations, 0 ].max
      # Primary confirmed mają pierwszeństwo, ale waitlisterzy kampanii też
      # łapią wolne sloty sub-eventu — kolejność: confirmed po position,
      # potem waitlist po position.
      ordered = confirmed_candidates + waitlist_candidates
      to_confirm = ordered.first(open_slots)
      to_waitlist = ordered.drop(open_slots)

      next_confirmed_pos = (event.participations.confirmed.maximum(:position) || 0) + 1
      next_waitlist_pos  = (event.participations.waitlist.maximum(:position)  || 0) + 1

      to_confirm.each_with_index do |uid, idx|
        event.participations.create!(user_id: uid, status: :confirmed, position: next_confirmed_pos + idx)
      end
      to_waitlist.each_with_index do |uid, idx|
        event.participations.create!(user_id: uid, status: :waitlist, position: next_waitlist_pos + idx)
      end
    end
  end
end
