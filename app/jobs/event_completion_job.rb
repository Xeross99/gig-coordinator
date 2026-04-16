class EventCompletionJob < ApplicationJob
  queue_as :default

  def perform
    Event.awaiting_completion.find_each do |event|
      event.participations.confirmed.includes(:user).find_each do |participation|
        CompletedEventMailer.with(participation: participation).notify.deliver_later
        WebPushNotifier.perform_later(:completion, participation_id: participation.id)
      end
      event.update!(completed_at: Time.current)
    end
  end
end
