require "test_helper"

class CampaignParticipationResequenceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @host = hosts(:jan)
    @campaign = build_campaign(capacity: 6)
  end

  def build_campaign(capacity:)
    c = EventCampaign.create!(host: @host, name: "Resequence test", capacity: capacity)
    c.campaign_participations.destroy_all
    c
  end

  def add_cp_users(campaign, status:, count:, starting_position: 1)
    count.times.map do |i|
      pos = starting_position + i
      u = User.create!(first_name: "#{status}#{pos}", last_name: "U", email: "cp_#{status}#{pos}_#{campaign.id}@test.example")
      CampaignParticipation.create!(event_campaign: campaign, user: u, status: status, position: pos)
    end
  end

  def positions_for(campaign, status)
    campaign.campaign_participations.where(status: status).order(:position).pluck(:position)
  end

  # --- resequence! unit tests ---

  test "resequence! compacts gaps in waitlist positions" do
    w1 = add_cp_users(@campaign, status: :waitlist, count: 1, starting_position: 3).first
    w2 = add_cp_users(@campaign, status: :waitlist, count: 1, starting_position: 7).first
    w3 = add_cp_users(@campaign, status: :waitlist, count: 1, starting_position: 12).first

    CampaignParticipation.resequence!(@campaign, :waitlist)

    assert_equal [ 1, 2, 3 ], positions_for(@campaign, :waitlist)
    assert_equal 1, w1.reload.position
    assert_equal 2, w2.reload.position
    assert_equal 3, w3.reload.position
  end

  test "resequence! compacts gaps in confirmed positions" do
    c1 = add_cp_users(@campaign, status: :confirmed, count: 1, starting_position: 1).first
    c2 = add_cp_users(@campaign, status: :confirmed, count: 1, starting_position: 5).first
    c3 = add_cp_users(@campaign, status: :confirmed, count: 1, starting_position: 9).first

    CampaignParticipation.resequence!(@campaign, :confirmed)

    assert_equal [ 1, 2, 3 ], positions_for(@campaign, :confirmed)
  end

  test "resequence! preserves relative order" do
    w1 = add_cp_users(@campaign, status: :waitlist, count: 1, starting_position: 5).first
    w2 = add_cp_users(@campaign, status: :waitlist, count: 1, starting_position: 2).first
    w3 = add_cp_users(@campaign, status: :waitlist, count: 1, starting_position: 8).first

    CampaignParticipation.resequence!(@campaign, :waitlist)

    ordered_ids = @campaign.campaign_participations.waitlist.order(:position).pluck(:id)
    assert_equal [ w2.id, w1.id, w3.id ], ordered_ids
    assert_equal [ 1, 2, 3 ], positions_for(@campaign, :waitlist)
  end

  test "resequence! is a no-op when positions are already contiguous" do
    add_cp_users(@campaign, status: :waitlist, count: 3, starting_position: 1)

    assert_no_changes -> { positions_for(@campaign, :waitlist) } do
      CampaignParticipation.resequence!(@campaign, :waitlist)
    end
  end

  test "resequence! handles empty list" do
    assert_nothing_raised do
      CampaignParticipation.resequence!(@campaign, :waitlist)
    end
  end

  test "resequence! does not affect other statuses" do
    add_cp_users(@campaign, status: :confirmed, count: 2, starting_position: 5)
    add_cp_users(@campaign, status: :waitlist, count: 2, starting_position: 10)

    CampaignParticipation.resequence!(@campaign, :waitlist)

    assert_equal [ 5, 6 ], positions_for(@campaign, :confirmed)
    assert_equal [ 1, 2 ], positions_for(@campaign, :waitlist)
  end

  test "resequence! does not trigger model callbacks (uses update_column)" do
    add_cp_users(@campaign, status: :waitlist, count: 2, starting_position: 5)

    assert_no_enqueued_jobs do
      CampaignParticipation.resequence!(@campaign, :waitlist)
    end
  end

  # --- Integration: cancel confirmed → positions stay contiguous ---

  # Goły `update!(status: :cancelled)` — bez ręcznego promote/resequence —
  # musi zostawić spójny primary roster; promocję i resequence robi callback
  # modelu (cascade_cancellation). To jest kontrakt „działa z konsoli".
  test "canceling a confirmed campaign participant promotes a waitlister and leaves contiguous positions" do
    confirmed = add_cp_users(@campaign, status: :confirmed, count: 4, starting_position: 1)
    waitlist = add_cp_users(@campaign, status: :waitlist, count: 5, starting_position: 1)

    confirmed[1].update!(status: :cancelled)

    assert_equal (1..4).to_a, positions_for(@campaign, :confirmed)
    assert_equal (1..4).to_a, positions_for(@campaign, :waitlist)
    assert waitlist.first.reload.confirmed?, "oldest primary waitlister must be auto-promoted"
  end

  test "canceling multiple confirmed promotes waitlisters and leaves contiguous positions" do
    confirmed = add_cp_users(@campaign, status: :confirmed, count: 5, starting_position: 1)
    waitlist = add_cp_users(@campaign, status: :waitlist, count: 3, starting_position: 1)

    confirmed[0].update!(status: :cancelled)
    confirmed[2].update!(status: :cancelled)
    confirmed[4].update!(status: :cancelled)

    # Każdy cancel promuje jednego waitlistera — 3 cancels, 3 promocje.
    assert_equal [ 1, 2, 3, 4, 5 ], positions_for(@campaign, :confirmed)
    assert_equal [], positions_for(@campaign, :waitlist)
    assert waitlist.all? { |w| w.reload.confirmed? }
  end

  test "canceling a waitlist campaign participant leaves contiguous positions" do
    add_cp_users(@campaign, status: :confirmed, count: 4, starting_position: 1)
    waitlist = add_cp_users(@campaign, status: :waitlist, count: 5, starting_position: 1)

    waitlist[2].update!(status: :cancelled)

    assert_equal (1..4).to_a, positions_for(@campaign, :waitlist)
    remaining = @campaign.campaign_participations.waitlist.order(:position).pluck(:user_id)
    assert_equal [ waitlist[0], waitlist[1], waitlist[3], waitlist[4] ].map(&:user_id), remaining
  end

  test "promotion from campaign waitlist resequences positions" do
    add_cp_users(@campaign, status: :confirmed, count: 3, starting_position: 1)
    waitlist = add_cp_users(@campaign, status: :waitlist, count: 4, starting_position: 1)

    CampaignReservationService.promote_from_waitlist(@campaign)

    assert_equal (1..3).to_a, positions_for(@campaign, :waitlist)
    ordered_users = @campaign.campaign_participations.waitlist.order(:position).map(&:user)
    assert_equal [ waitlist[1].user, waitlist[2].user, waitlist[3].user ], ordered_users
  end

  test "repeated promotions maintain contiguous positions" do
    add_cp_users(@campaign, status: :confirmed, count: 2, starting_position: 1)
    waitlist = add_cp_users(@campaign, status: :waitlist, count: 5, starting_position: 1)

    3.times { CampaignReservationService.promote_from_waitlist(@campaign) }

    assert_equal (1..2).to_a, positions_for(@campaign, :waitlist)
    assert_equal (1..5).to_a, positions_for(@campaign, :confirmed)
  end

  # --- Campaign cascade to sub-events ---

  test "cascade cancel to sub-events leaves contiguous positions on sub-events" do
    campaign = build_campaign(capacity: 3)
    u1 = User.create!(first_name: "U1", last_name: "X", email: "u1_cascade@test.example")
    u2 = User.create!(first_name: "U2", last_name: "X", email: "u2_cascade@test.example")
    u3 = User.create!(first_name: "U3", last_name: "X", email: "u3_cascade@test.example")
    u4 = User.create!(first_name: "U4", last_name: "X", email: "u4_cascade@test.example")

    CampaignParticipation.create!(event_campaign: campaign, user: u1, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: u2, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: u3, status: :confirmed, position: 3)
    CampaignParticipation.create!(event_campaign: campaign, user: u4, status: :waitlist, position: 1)

    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 3
    )
    sub.participations.destroy_all
    Participation.create!(event: sub, user: u1, status: :confirmed, position: 1)
    Participation.create!(event: sub, user: u2, status: :confirmed, position: 2)
    Participation.create!(event: sub, user: u3, status: :confirmed, position: 3)
    Participation.create!(event: sub, user: u4, status: :waitlist, position: 1)

    EventCampaign.transaction do
      campaign.lock!
      cp = campaign.campaign_participations.find_by(user: u2)
      cp.update!(status: :cancelled)
      promoted_cp = campaign.campaign_participations.waitlist.order(:position).first
      if promoted_cp
        pos = (campaign.campaign_participations.confirmed.maximum(:position) || 0) + 1
        promoted_cp.skip_sub_event_sync = true
        promoted_cp.update!(status: :confirmed, position: pos)
      end
      CampaignParticipation.resequence!(campaign, :confirmed)
      CampaignParticipation.resequence!(campaign, :waitlist)
    end

    campaign.events.where("scheduled_at > ?", Time.current).find_each do |event|
      Event.transaction do
        event.lock!
        p = event.participations.active.find_by(user_id: u2.id)
        next unless p
        p.update!(status: :cancelled)
        sub_promoted = event.participations.waitlist.order(:position).first
        if sub_promoted
          pos = (event.participations.confirmed.maximum(:position) || 0) + 1
          sub_promoted.update!(status: :confirmed, position: pos)
        end
        Participation.resequence!(event, :confirmed)
        Participation.resequence!(event, :waitlist)
      end
    end

    sub_confirmed = sub.participations.where(status: :confirmed).order(:position).pluck(:position)
    sub_waitlist = sub.participations.where(status: :waitlist).order(:position).pluck(:position)
    assert_equal (1..sub_confirmed.size).to_a, sub_confirmed
    assert_equal (1..sub_waitlist.size).to_a, sub_waitlist
  end
end
