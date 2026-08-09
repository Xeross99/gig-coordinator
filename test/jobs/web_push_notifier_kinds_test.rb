require "test_helper"

class WebPushNotifierKindsTest < ActiveJob::TestCase
  # Podpinamy się pod send_web_push, żeby zebrać cele bez gadania z VAPID.
  # Zwraca listę [sub_id, payload].
  def capture_sends(job)
    sent = []
    job.define_singleton_method(:send_web_push) { |sub, payload| sent << [ sub.id, payload ] }
    sent
  end

  # --- :swap_proposal ----------------------------------------------------------

  class SwapKinds < WebPushNotifierKindsTest
    setup do
      @event    = events(:chickens_tomorrow)
      @proposer = users(:ala)
      @target   = users(:bartek)
      Participation.create!(event: @event, user: @target,   status: :confirmed, position: 1)
      Participation.create!(event: @event, user: @proposer, status: :waitlist,  position: 1)
      @proposal = SwapProposal.create!(event: @event, proposer: @proposer, target: @target,
                                       expires_at: SwapProposal::EXPIRATION_WINDOW.from_now)

      @proposer_sub = PushSubscription.create!(user: @proposer, endpoint: "https://example.com/proposer",
                                               p256dh_key: "p", auth_key: "a")
      @target_sub   = PushSubscription.create!(user: @target, endpoint: "https://example.com/target",
                                               p256dh_key: "p", auth_key: "a")
    end

    test ":swap_proposal targets ONLY the target" do
      job  = WebPushNotifier.new
      sent = capture_sends(job)
      job.perform(:swap_proposal, swap_proposal_id: @proposal.id)

      assert_equal [ @target_sub.id ], sent.map(&:first)
    end

    test ":swap_proposal no-ops when the proposal is no longer pending" do
      @proposal.update!(status: :accepted)
      job  = WebPushNotifier.new
      sent = capture_sends(job)
      job.perform(:swap_proposal, swap_proposal_id: @proposal.id)

      assert_empty sent
    end

    test ":swap_accepted targets ONLY the proposer and only when accepted" do
      job  = WebPushNotifier.new
      sent = capture_sends(job)

      # still pending → no-op
      job.perform(:swap_accepted, swap_proposal_id: @proposal.id)
      assert_empty sent

      @proposal.update!(status: :accepted)
      job.perform(:swap_accepted, swap_proposal_id: @proposal.id)
      assert_equal [ @proposer_sub.id ], sent.map(&:first)
    end

    test ":swap_declined targets ONLY the proposer and only when declined" do
      job  = WebPushNotifier.new
      sent = capture_sends(job)

      # still pending → no-op
      job.perform(:swap_declined, swap_proposal_id: @proposal.id)
      assert_empty sent

      @proposal.update!(status: :declined)
      job.perform(:swap_declined, swap_proposal_id: @proposal.id)
      assert_equal [ @proposer_sub.id ], sent.map(&:first)
    end
  end

  # --- :sub_event_added --------------------------------------------------------

  class SubEventAdded < WebPushNotifierKindsTest
    setup do
      @host     = hosts(:jan)
      @campaign = EventCampaign.create!(host: @host, name: "Kampania", capacity: 5)
      @campaign.campaign_participations.destroy_all
      @sub = Event.create!(host: @host, event_campaign: @campaign, name: "Sub",
                           scheduled_at: 3.days.from_now, ends_at: 3.days.from_now + 2.hours,
                           pay_per_person: 100, capacity: 5)

      @member   = users(:ala)
      @waiter    = users(:bartek)
      CampaignParticipation.create!(event_campaign: @campaign, user: @member, status: :confirmed, position: 1)
      CampaignParticipation.create!(event_campaign: @campaign, user: @waiter, status: :waitlist,  position: 1)

      @member_sub = PushSubscription.create!(user: @member, endpoint: "https://example.com/member",
                                             p256dh_key: "p", auth_key: "a")
      @waiter_sub = PushSubscription.create!(user: @waiter, endpoint: "https://example.com/waiter",
                                             p256dh_key: "p", auth_key: "a")
    end

    test ":sub_event_added targets ONLY confirmed campaign members" do
      job  = WebPushNotifier.new
      sent = capture_sends(job)
      job.perform(:sub_event_added, event_id: @sub.id)

      assert_equal [ @member_sub.id ], sent.map(&:first),
                   "waitlist campaign member is not a confirmed member yet"
    end
  end
end
