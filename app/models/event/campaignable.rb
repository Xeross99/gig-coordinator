module Event::Campaignable
  extend ActiveSupport::Concern

  # An event with `event_campaign_id` is a sub-event of a series: it inherits the
  # campaign's primary roster instead of seeding its own reservations, and it
  # stays out of the global feed.

  included do
    after_create_commit :revive_completed_campaign, if: :upcoming_sub_event?
    after_create_commit :seed_from_campaign_roster, if: :upcoming_sub_event?
    after_create_commit :notify_sub_event_added,    if: :upcoming_sub_event?
  end

  private

  def upcoming_sub_event?
    upcoming_now? && event_campaign_id.present?
  end

  # Dorzucenie przyszłego zlecenia do zakończonej serii przywraca kampanię
  # do aktywnych — scope `EventCampaign.active` wymaga `completed_at: nil`,
  # więc bez tego nowy termin byłby niewidoczny w feedzie. EventCompletionJob
  # oznaczy kampanię ponownie jako ukończoną, gdy wszystkie sub-eventy się odbędą.
  def revive_completed_campaign
    event_campaign.update!(completed_at: nil) if event_campaign.completed?
  end

  def seed_from_campaign_roster
    CampaignSubEventSeeder.call(self)
  end

  # Push o nowym terminie idzie do confirmed członków serii, a nie globalnie —
  # globalny `:new_event` obsługuje tylko zwykłe zlecenia.
  def notify_sub_event_added
    WebPushNotifier.perform_later(:sub_event_added, event_id: id)
  end
end
