module EventCampaignsHelper
  PREVIEW_LIMIT = 3

  CampaignCard = Struct.new(:preview, :extra_count, :statuses, :slots_taken, keyword_init: true)

  # Wszystko, czego potrzebuje karta kampanii, policzone raz. Feed batchuje te
  # dane w kontrolerze (3 zapytania na cały feed) i podaje je jako locals;
  # broadcast renderuje kartę bez nich, więc każdy kawałek ma fallback na
  # własne zapytanie. Bez tego partial musiał trzymać dziesięć przypisań
  # z zapytaniami w środku.
  def campaign_card(campaign, upcoming: nil, statuses: nil, slots_taken: nil)
    all_upcoming = upcoming || campaign.events.upcoming.to_a
    preview      = all_upcoming.first(PREVIEW_LIMIT)

    CampaignCard.new(
      preview:     preview,
      extra_count: [ all_upcoming.size - PREVIEW_LIMIT, 0 ].max,
      statuses:    statuses || my_sub_event_statuses(preview),
      slots_taken: slots_taken || campaign.slots_taken
    )
  end

  private

  # event_id → status uczestnictwa zalogowanego usera na sub-eventach z podglądu.
  def my_sub_event_statuses(events)
    return {} if Current.user.nil? || events.empty?

    Current.user.participations
           .where(event_id: events.map(&:id))
           .where.not(status: :cancelled)
           .index_by(&:event_id)
           .transform_values(&:status)
  end
end
