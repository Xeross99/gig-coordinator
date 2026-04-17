class ReservationExpirationJob < ApplicationJob
  queue_as :default

  def perform
    ReservationService.expire_stale!
  end
end
