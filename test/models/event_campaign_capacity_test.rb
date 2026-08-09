require "test_helper"

class EventCampaignCapacityTest < ActiveSupport::TestCase
  setup do
    @host = hosts(:jan)
    @a = users(:ala)
    @b = users(:bartek)
    @c = users(:cezary)
  end

  # Campaign with no mistrz_piora → seed_reservations is a no-op, so the primary
  # roster starts empty and we build it explicitly.
  def build_campaign(capacity:, sub_capacity: nil)
    campaign = EventCampaign.create!(host: @host, name: "Cap test", capacity: capacity)
    campaign.campaign_participations.destroy_all
    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 3.days.from_now, ends_at: 3.days.from_now + 2.hours,
      pay_per_person: 100, capacity: sub_capacity || capacity
    )
    sub.participations.destroy_all
    [ campaign, sub ]
  end

  def cp(campaign, user)
    campaign.campaign_participations.find_by(user_id: user.id)
  end

  # participation_counts (slots_taken/full?) jest memoizowane, a AR-owy #reload
  # nie czyści zwykłych ivarów — po dopisaniu uczestnictw trzeba pobrać świeży
  # obiekt z bazy, żeby licznik był aktualny (w produkcji każdy request ma nowy).
  def fresh(campaign)
    EventCampaign.find(campaign.id)
  end

  # --- slots_taken / full? -----------------------------------------------------

  test "slots_taken counts confirmed + reserved but NOT waitlist" do
    campaign, = build_campaign(capacity: 5)
    CampaignParticipation.create!(event_campaign: campaign, user: @a, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @b, status: :reserved,
                                  position: 1, reserved_until: 2.hours.from_now)
    CampaignParticipation.create!(event_campaign: campaign, user: @c, status: :waitlist, position: 1)

    assert_equal 2, fresh(campaign).slots_taken, "confirmed + reserved, waitlist excluded"
  end

  test "full? is true exactly at capacity boundary" do
    campaign, = build_campaign(capacity: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @a, status: :confirmed, position: 1)
    refute fresh(campaign).full?, "1 of 2 slots taken — not full"

    CampaignParticipation.create!(event_campaign: campaign, user: @b, status: :confirmed, position: 2)
    assert fresh(campaign).full?, "2 of 2 slots taken — full"
  end

  # --- capacity increase -------------------------------------------------------

  test "increasing capacity of a full campaign promotes the oldest primary waitlister" do
    campaign, sub = build_campaign(capacity: 2, sub_capacity: 3)
    CampaignParticipation.create!(event_campaign: campaign, user: @a, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @b, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @c, status: :waitlist,  position: 1)

    assert fresh(campaign).full?
    assert_equal "waitlist", cp(campaign, @c).status

    campaign.update!(capacity: 3)

    assert_equal "confirmed", cp(campaign.reload, @c).status,
                 "the oldest primary waitlister is promoted into the freed slot"
  end

  test "capacity increase cascades the promotion onto upcoming sub-events" do
    # Sub cap 2 = pełny po dwóch primary confirmed, więc C startuje na jego
    # waitliście; promocja primary sama w sobie nie robi miejsca na subie.
    campaign, sub = build_campaign(capacity: 2, sub_capacity: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @a, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @b, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @c, status: :waitlist,  position: 1)

    assert_equal "waitlist", sub.participations.find_by(user_id: @c.id).status

    campaign.update!(capacity: 3)

    assert_equal "confirmed", cp(campaign.reload, @c).status
    assert_equal "waitlist", sub.participations.find_by(user_id: @c.id).reload.status,
                 "pełny sub-event nie puchnie od promocji na primary"
  end

  test "capacity increase promotes the sub-confirmed waitlister on primary without touching the sub roster" do
    # Sub cap 3 > primary cap 2 — C (waitlister kampanii) od razu łapie wolny
    # slot sub-eventu; późniejsza promocja na primary nie może go zdublować
    # ani przetasować.
    campaign, sub = build_campaign(capacity: 2, sub_capacity: 3)
    CampaignParticipation.create!(event_campaign: campaign, user: @a, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @b, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @c, status: :waitlist,  position: 1)

    assert_equal "confirmed", sub.participations.find_by(user_id: @c.id).status,
                 "waitlister kampanii łapie wolny slot sub-eventu"

    campaign.update!(capacity: 3)

    assert_equal "confirmed", cp(campaign.reload, @c).status
    assert_equal [ @a.id, @b.id, @c.id ],
                 sub.participations.confirmed.order(:position).pluck(:user_id),
                 "roster sub-eventu bez zmian i bez duplikatów"
  end

  # --- capacity decrease -------------------------------------------------------

  test "decreasing capacity demotes the most-recently-confirmed to waitlist" do
    campaign, = build_campaign(capacity: 3)
    CampaignParticipation.create!(event_campaign: campaign, user: @a, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @b, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @c, status: :confirmed, position: 3)

    campaign.update!(capacity: 2)

    assert_equal "confirmed", cp(campaign, @a).status, "oldest confirmed stays"
    assert_equal "confirmed", cp(campaign, @b).status
    assert_equal "waitlist",  cp(campaign, @c).status, "highest-position confirmed is demoted"
  end
end
