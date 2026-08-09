require "test_helper"

# :carpool_offered — push „X oferuje się jako kierowca" do głównej listy
# (confirmed) eventu, bez samego kierowcy i bez waitlisty.
class WebPushNotifierCarpoolOfferedTest < ActiveJob::TestCase
  setup do
    @event      = events(:chickens_tomorrow)
    @driver     = users(:ala)
    @confirmed  = users(:bartek)
    @waitlister = users(:cezary)
    @driver.update!(can_drive: true)
    Participation.create!(event: @event, user: @driver,     status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @confirmed,  status: :confirmed, position: 2)
    Participation.create!(event: @event, user: @waitlister, status: :waitlist,  position: 1)

    @driver_sub     = PushSubscription.create!(user: @driver,     endpoint: "https://example.com/d", p256dh_key: "p", auth_key: "a")
    @confirmed_sub  = PushSubscription.create!(user: @confirmed,  endpoint: "https://example.com/c", p256dh_key: "p", auth_key: "a")
    @waitlister_sub = PushSubscription.create!(user: @waitlister, endpoint: "https://example.com/w", p256dh_key: "p", auth_key: "a")
  end

  def capture_sends(job)
    sent = []
    job.define_singleton_method(:send_web_push) { |sub, payload| sent << [ sub.id, payload ] }
    sent
  end

  test "utworzenie oferty kierowcy enqueue'uje :carpool_offered" do
    assert_enqueued_with(job: WebPushNotifier) do
      CarpoolOffer.create!(event: @event, user: @driver)
    end
    offered = enqueued_jobs.any? do |j|
      j["job_class"] == "WebPushNotifier" &&
        ActiveJob::Arguments.deserialize(j["arguments"]).first == :carpool_offered
    end
    assert offered, "wśród jobów powinien być :carpool_offered"
  end

  test ":carpool_offered targetuje confirmed bez kierowcy i bez waitlisty" do
    offer = CarpoolOffer.create!(event: @event, user: @driver)

    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_offered, carpool_offer_id: offer.id)

    sub_ids = sent.map(&:first)
    assert_includes sub_ids, @confirmed_sub.id, "confirmed z głównej listy dostaje pusha"
    refute_includes sub_ids, @driver_sub.id,     "kierowca nie dostaje pusha o samym sobie"
    refute_includes sub_ids, @waitlister_sub.id, "waitlista nie dostaje pusha"

    payload = sent.first.last
    assert_match @driver.display_name, payload[:body]
    assert_match "kierowca", payload[:body]
    assert_equal "/eventy/#{@event.to_param}", payload[:url]
  end

  test ":carpool_offered na sub-evencie kampanii wymienia rzut w treści" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Wielki rzut", capacity: 2)
    campaign.campaign_participations.destroy_all
    sub_event = Event.create!(
      host: hosts(:jan), event_campaign: campaign, name: "Łapanie w rzucie",
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
      pay_per_person: 50, capacity: 2
    )
    Participation.create!(event: sub_event, user: @driver,    status: :confirmed, position: 1)
    Participation.create!(event: sub_event, user: @confirmed, status: :confirmed, position: 2)
    offer = CarpoolOffer.create!(event: sub_event, user: @driver)

    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_offered, carpool_offer_id: offer.id)

    payload = sent.first.last
    assert_match "Wielki rzut", payload[:body], "treść wymienia nazwę rzutu"
  end

  test ":carpool_offered no-op gdy event już wystartował lub oferta znikła" do
    offer = CarpoolOffer.create!(event: @event, user: @driver)
    @event.update_column(:scheduled_at, 1.hour.ago)

    job = WebPushNotifier.new
    sent = capture_sends(job)
    job.perform(:carpool_offered, carpool_offer_id: offer.id)
    assert_empty sent

    assert_nothing_raised { WebPushNotifier.new.perform(:carpool_offered, carpool_offer_id: -1) }
  end
end
