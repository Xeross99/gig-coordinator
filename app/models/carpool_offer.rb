class CarpoolOffer < ApplicationRecord
  SEATS = 4

  belongs_to :event
  belongs_to :user
  belongs_to :current_pickup_user, class_name: "User", optional: true

  has_many :carpool_requests, dependent: :destroy

  enum :trip_state, { not_started: 0, en_route: 1, picking_up: 2 }

  validates :user_id, uniqueness: { scope: :event_id }
  validate  :user_is_event_participant
  validate  :user_has_driver_permission
  validate  :user_is_not_passenger
  validate  :pickup_user_is_accepted_passenger

  after_commit on: %i[create update destroy] do
    EventRosterBroadcastJob.perform_later(event_id: event_id)
  end
  after_create_commit { WebPushNotifier.perform_later(:carpool_offered, carpool_offer_id: id) }

  # Gdy asocjacja jest już załadowana (preload z Event#roster_data), filtrujemy
  # w pamięci — scope `.accepted` ominąłby preload i strzelał do bazy per oferta.
  def accepted_requests
    return carpool_requests.select(&:accepted?) if carpool_requests.loaded?

    carpool_requests.accepted
  end

  def pending_requests
    return carpool_requests.select(&:pending?) if carpool_requests.loaded?

    carpool_requests.pending
  end

  def seats_taken
    accepted_requests.size
  end

  def seats_left
    SEATS - seats_taken
  end

  def full?
    seats_left <= 0
  end

  # Pasażerowie w kolejności odbierania ustalonej przez kierowcę w modalu
  # „Wyjeżdżam" (CarpoolRequest#pickup_position). Pasażerowie bez pozycji —
  # np. zaakceptowani już po wyjeździe albo sprzed wprowadzenia kolejności —
  # lądują na końcu, w kolejności potwierdzenia (updated_at).
  def passengers_in_pickup_order
    accepted_requests
      .sort_by { |r| [ r.pickup_position || Float::INFINITY, r.updated_at ] }
      .map(&:user)
  end

  def first_pickup_user
    passengers_in_pickup_order.first
  end

  # State transitions used by CarpoolTripsController. Wszystkie idą przez
  # zwykły `update!`, więc after_commit z broadcastem rostera odpala automatycznie.
  # `ordered_user_ids` to kolejność odbierania z modalu „Wyjeżdżam" — brak
  # (API bez parametru) zostawia dotychczasowe pozycje / kolejność potwierdzenia.
  def depart!(ordered_user_ids = nil)
    transaction do
      assign_pickup_positions(ordered_user_ids) if ordered_user_ids.present?
      update!(trip_state: :en_route, current_pickup_user: nil)
    end
  end

  def arrive_at!(user)
    update!(trip_state: :picking_up, current_pickup_user: user)
  end

  def cancel_trip!
    update!(trip_state: :not_started, current_pickup_user: nil)
  end

  private

  # Id spoza zaakceptowanych pasażerów są ignorowane; zaakceptowani pominięci
  # w liście (np. potwierdzeni już po otwarciu modalu) lądują na końcu,
  # w kolejności potwierdzenia.
  def assign_pickup_positions(ordered_user_ids)
    ordered_ids = ordered_user_ids.map(&:to_i)
    carpool_requests.accepted
                    .sort_by { |r| [ ordered_ids.index(r.user_id) || Float::INFINITY, r.updated_at ] }
                    .each_with_index { |r, i| r.update!(pickup_position: i + 1) }
  end

  def pickup_user_is_accepted_passenger
    return if current_pickup_user_id.blank?
    return if carpool_requests.accepted.where(user_id: current_pickup_user_id).exists?

    errors.add(:current_pickup_user_id, "musi być zaakceptowanym pasażerem")
  end

  def user_is_not_passenger
    return if event.blank? || user.blank?

    passenger = CarpoolRequest.joins(:carpool_offer)
                              .where(carpool_offers: { event_id: event_id })
                              .where(user_id: user_id)
                              .where.not(status: :declined)
                              .exists?
    errors.add(:base, "nie możesz być kierowcą — jesteś już pasażerem na tym zleceniu") if passenger
  end

  def user_is_event_participant
    return if event.blank? || user.blank?
    return if event.participations.where(user_id: user_id, status: :confirmed).exists?

    errors.add(:base, "tylko zapisani uczestnicy zlecenia mogą zgłosić się jako kierowca")
  end

  def user_has_driver_permission
    return if user.blank?

    errors.add(:base, "nie masz uprawnień kierowcy — poproś administratora") unless user.can_drive?
  end
end
