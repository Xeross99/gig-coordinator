require "test_helper"

class WebPushNotifierCarpoolTest < ActiveJob::TestCase
  setup do
    @event     = events(:gig_coordinators_tomorrow)
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
end
