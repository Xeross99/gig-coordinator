require "test_helper"

class EventCampaignTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @host = hosts(:jan)
  end

  def build_campaign(capacity: 4, name: "Rzut testowy")
    c = EventCampaign.create!(host: @host, name: name, capacity: capacity)
    c.campaign_participations.destroy_all
    clear_enqueued_jobs
    c
  end

  def add_sub_event(campaign, name:, capacity: 4, scheduled_at: 2.days.from_now)
    Event.create!(
      host: @host, event_campaign: campaign, name: name,
      scheduled_at: scheduled_at, ends_at: scheduled_at + 2.hours,
      pay_per_person: 50, capacity: capacity
    )
  end

  def make_user(label)
    User.create!(first_name: label, last_name: "Testowy",
                 email: "camp_#{label.downcase}_#{SecureRandom.hex(3)}@test.example")
  end

  test "sub_event_progress_for returns [zero, zero] when campaign has no upcoming sub-events" do
    campaign = build_campaign
    user = make_user("Adam")

    assert_equal [ 0, 0 ], campaign.sub_event_progress_for(user)
  end

  test "sub_event_progress_for counts active participations against all upcoming sub-events" do
    campaign = build_campaign(capacity: 4)
    add_sub_event(campaign, name: "Łapanie 1")
    add_sub_event(campaign, name: "Łapanie 2", scheduled_at: 3.days.from_now)

    user = make_user("Bartek")
    CampaignParticipation.create!(event_campaign: campaign, user: user, status: :confirmed, position: 1)

    # Auto-zapis (enroll_in_sub_events) rozsiewa usera na oba nadchodzące sub-eventy.
    assert_equal [ 2, 2 ], campaign.sub_event_progress_for(user)
  end

  test "sub_event_progress_for ignores past sub-events" do
    campaign = build_campaign
    add_sub_event(campaign, name: "Przyszłe łapanie")
    add_sub_event(campaign, name: "Minione łapanie", scheduled_at: 2.days.ago)

    user = make_user("Cezary")
    CampaignParticipation.create!(event_campaign: campaign, user: user, status: :confirmed, position: 1)

    active, total = campaign.sub_event_progress_for(user)
    assert_equal 1, total, "tylko nadchodzący sub-event liczy się do total"
    assert_equal 1, active
  end
end
