require "test_helper"

class WebPushNotifierCarpoolTest < ActiveJob::TestCase
  setup do
    @event     = events(:chickens_tomorrow)
    @driver    = users(:ala)
    @passenger = users(:bartek)
    Participation.create!(event: @event, user: @driver,    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @passenger, status: :confirmed, position: 2)
    @offer   = CarpoolOffer.create!(event: @event, user: @driver)
    @request = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)

    @driver_sub    = PushSubscription.create!(user: @driver,    endpoint: "https://example.com/driver",    p256dh_key: "p", auth_key: "a")
    @passenger_sub = PushSubscription.create!(user: @passenger, endpoint: "https://example.com/passenger", p256dh_key: "p", auth_key: "a")
  end

  # Podpinamy się pod send_web_push żeby zbierać cele i payloady bez gadania z VAPID.
  def capture_sends(job)
    sent = []
    job.define_singleton_method(:send_web_push) { |sub, payload| sent << [ sub.id, payload ] }
    sent
  end

  test ":carpool_ask targets the driver" do
    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_ask, carpool_request_id: @request.id)

    assert_equal 1, sent.size
    sub_id, payload = sent.first
    assert_equal @driver_sub.id, sub_id
    assert_match @passenger.display_name, payload[:body]
    assert_match @event.name,             payload[:body]
    assert_equal "/eventy/#{@event.to_param}", payload[:url]
  end

  test ":carpool_accepted targets the passenger" do
    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_accepted, carpool_request_id: @request.id)

    assert_equal [ @passenger_sub.id ], sent.map(&:first)
    assert_match "Masz podwózkę", sent.first.last[:title]
  end

  test ":carpool_declined targets the passenger" do
    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_declined, carpool_request_id: @request.id)

    assert_equal [ @passenger_sub.id ], sent.map(&:first)
    assert_match "Brak miejsca", sent.first.last[:title]
  end

  test "no-op when request has been deleted" do
    id = @request.id
    @request.destroy
    job = WebPushNotifier.new
    sent = capture_sends(job)
    assert_nothing_raised { job.perform(:carpool_ask, carpool_request_id: id) }
    assert_equal 0, sent.size
  end

  # ---- Trip status pings (depart / at_pickup / progress / cancel) ----

  def trip_setup
    # Akceptujemy podstawowego pasażera + dodajemy drugiego.
    @request.update!(status: :accepted)
    @other = users(:cezary)
    Participation.create!(event: @event, user: @other, status: :confirmed, position: 3)
    @other_request = CarpoolRequest.create!(carpool_offer: @offer, user: @other, status: :accepted)
    @other_sub = PushSubscription.create!(user: @other, endpoint: "https://example.com/other", p256dh_key: "p", auth_key: "a")
  end

  test ":carpool_departed targets every accepted passenger" do
    trip_setup
    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_departed, carpool_offer_id: @offer.id)

    target_ids = sent.map(&:first).sort
    assert_equal [ @passenger_sub.id, @other_sub.id ].sort, target_ids
    refute_includes target_ids, @driver_sub.id
    assert_match "wyjechał", sent.first.last[:body]
  end

  test ":carpool_departed personalizuje treść wg kolejności odbierania" do
    trip_setup
    @offer.depart!([ @other.id, @passenger.id ])

    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_departed, carpool_offer_id: @offer.id)

    bodies = sent.to_h { |sub_id, payload| [ sub_id, payload[:body] ] }
    assert_match "jedzie najpierw po Ciebie",                bodies[@other_sub.id]
    assert_match "najpierw jedzie po: #{@other.display_name}", bodies[@passenger_sub.id]
  end

  test ":carpool_at_pickup targets ONLY the picked-up passenger" do
    trip_setup
    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_at_pickup, carpool_offer_id: @offer.id, user_id: @passenger.id)

    assert_equal [ @passenger_sub.id ], sent.map(&:first)
    assert_match "czeka pod Twoim domem", sent.first.last[:title]
  end

  test ":carpool_progress targets every accepted passenger EXCEPT the one being picked up" do
    trip_setup
    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_progress, carpool_offer_id: @offer.id, user_id: @passenger.id)

    # @passenger jest aktualnym pickup-em → on dostaje at_pickup, NIE progress.
    # @other dostaje progress („kierowca jest teraz u: @passenger").
    assert_equal [ @other_sub.id ], sent.map(&:first)
    assert_match @passenger.display_name, sent.first.last[:body]
  end

  test "trip pings no-op when offer has been deleted" do
    trip_setup
    id = @offer.id
    @offer.destroy
    job = WebPushNotifier.new
    sent = capture_sends(job)
    assert_nothing_raised { job.perform(:carpool_departed, carpool_offer_id: id) }
    %i[carpool_at_pickup carpool_progress].each do |kind|
      assert_nothing_raised { job.perform(kind, carpool_offer_id: id, user_id: @passenger.id) }
    end
    assert_equal 0, sent.size
  end
end
