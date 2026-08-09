class EventCompletionJob < ApplicationJob
  queue_as :default

  def perform
    Event.awaiting_completion.find_each do |event|
      event.participations.confirmed.includes(:user).find_each do |participation|
        WebPushNotifier.perform_later(:completion, participation_id: participation.id)
      end
      event.update!(completed_at: Time.current)

      # Jeśli to był ostatni nieukończony sub-event kampanii, oznacz całą
      # kampanię jako completed i wyślij push do każdego confirmed members.
      if (campaign = event.event_campaign) && all_sub_events_completed?(campaign)
        notify_campaign_completion(campaign)
        campaign.update!(completed_at: Time.current)
      end
    end
  end

  private

  def all_sub_events_completed?(campaign)
    campaign.events.any? && campaign.events.where(completed_at: nil).none?
  end

  def notify_campaign_completion(campaign)
    campaign.campaign_participations.confirmed.find_each do |cp|
      WebPushNotifier.perform_later(:campaign_completion, campaign_participation_id: cp.id)
    end
  end
end
