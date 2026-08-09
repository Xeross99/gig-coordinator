require "test_helper"

class CampaignParticipationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = hosts(:jan)
    users(:ala).update!(title:     :mistrz_piora)
    users(:bartek).update!(title:  :kurnikowy_gangster)
    users(:cezary).update!(title:  :kurzy_pacholek)
    users(:dominika).update!(title: :zoltodziob)

    @campaign = EventCampaign.create!(host: @host, name: "Cykl integracja", capacity: 4, creator: users(:ala))
    # zignoruj auto-seedowanego mistrza, każdy test sam buduje stan
    @campaign.campaign_participations.destroy_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    @sub = Event.create!(
      host: @host, event_campaign: @campaign, name: "Sub 1",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 2
    )
    @sub.participations.destroy_all
  end

  test "POST /kampanie/:id/uczestnictwo zapisuje świeżego usera na confirmed" do
    sign_in_as(users(:bartek))
    assert_difference -> { @campaign.campaign_participations.count }, +1 do
      post event_campaign_campaign_participation_path(@campaign)
    end
    cp = @campaign.campaign_participations.find_by(user: users(:bartek))
    assert_equal "confirmed", cp.status
    assert_redirected_to event_campaign_path(@campaign)
  end

  test "POST /kampanie/:id/uczestnictwo wpada na waitlist gdy primary pełny" do
    @campaign.update!(capacity: 1)
    CampaignParticipation.create!(event_campaign: @campaign, user: users(:cezary),
                                  status: :confirmed, position: 1)
    sign_in_as(users(:bartek))
    post event_campaign_campaign_participation_path(@campaign)
    cp = @campaign.campaign_participations.find_by(user: users(:bartek))
    assert_equal "waitlist", cp.status
  end

  test "POST /kampanie/:id/uczestnictwo reaktywuje cancelled (rejoin)" do
    cp = CampaignParticipation.create!(event_campaign: @campaign, user: users(:bartek),
                                       status: :cancelled, position: 0)
    sign_in_as(users(:bartek))
    assert_no_difference -> { @campaign.campaign_participations.count } do
      post event_campaign_campaign_participation_path(@campaign)
    end
    cp.reload
    assert_equal "confirmed", cp.status
  end

  test "POST /kampanie/:id/uczestnictwo blokuje zablokowanego usera" do
    HostBlock.create!(user: users(:bartek), host: @host)
    sign_in_as(users(:bartek))
    assert_no_difference -> { @campaign.campaign_participations.count } do
      post event_campaign_campaign_participation_path(@campaign)
    end
    assert_redirected_to event_campaign_path(@campaign)
    assert_match Copy::Participations::BLOCKED, flash[:alert]
  end

  test "DELETE /kampanie/:id/uczestnictwo canceluje kampanię i sub-eventy" do
    cp = CampaignParticipation.create!(event_campaign: @campaign, user: users(:bartek),
                                       status: :confirmed, position: 1)

    sign_in_as(users(:bartek))
    delete event_campaign_campaign_participation_path(@campaign)

    cp.reload
    assert_equal "cancelled", cp.status
    sub_p = @sub.participations.find_by(user: users(:bartek))
    assert_equal "cancelled", sub_p.reload.status
  end

  test "DELETE /kampanie/:id/uczestnictwo promuje z waitlisty po wypisaniu confirmed" do
    cp1 = CampaignParticipation.create!(event_campaign: @campaign, user: users(:bartek),
                                        status: :confirmed, position: 1)
    cp2 = CampaignParticipation.create!(event_campaign: @campaign, user: users(:cezary),
                                        status: :waitlist, position: 1)
    sign_in_as(users(:bartek))
    delete event_campaign_campaign_participation_path(@campaign)

    cp2.reload
    assert_equal "confirmed", cp2.status, "kolejny z waitlisty awansuje"
  end

  test "POST .../accept potwierdza rezerwację mistrza na primary rosterze" do
    cp = CampaignParticipation.create!(event_campaign: @campaign, user: users(:ala),
                                       status: :reserved, position: 1,
                                       reserved_until: 1.hour.from_now)
    sign_in_as(users(:ala))
    post accept_event_campaign_campaign_participation_path(@campaign)

    cp.reload
    assert_equal "confirmed", cp.status
    assert_nil cp.reserved_until
  end

  test "POST .../accept wpada na waitlist gdy primary pełny" do
    @campaign.update!(capacity: 1)
    CampaignParticipation.create!(event_campaign: @campaign, user: users(:bartek),
                                  status: :confirmed, position: 1)
    cp = CampaignParticipation.create!(event_campaign: @campaign, user: users(:ala),
                                       status: :reserved, position: 1,
                                       reserved_until: 1.hour.from_now)
    sign_in_as(users(:ala))
    post accept_event_campaign_campaign_participation_path(@campaign)

    cp.reload
    assert_equal "waitlist", cp.status
  end

  test "POST .../accept ignoruje wygasłe rezerwacje" do
    cp = CampaignParticipation.create!(event_campaign: @campaign, user: users(:ala),
                                       status: :reserved, position: 1,
                                       reserved_until: 1.minute.ago)
    sign_in_as(users(:ala))
    post accept_event_campaign_campaign_participation_path(@campaign)
    cp.reload
    assert_equal "reserved", cp.status, "wygasła rezerwacja zostaje do sweepera"
  end

  test "POST .../decline cancel-uje rezerwację i woła refill_one" do
    users(:bartek).update!(title: :mistrz_piora)
    cp = CampaignParticipation.create!(event_campaign: @campaign, user: users(:ala),
                                       status: :reserved, position: 1,
                                       reserved_until: 1.hour.from_now)
    sign_in_as(users(:ala))
    post decline_event_campaign_campaign_participation_path(@campaign)

    cp.reload
    assert_equal "cancelled", cp.status
    # Bartek (drugi mistrz) powinien dostać rezerwację po refill_one
    bartek_cp = @campaign.campaign_participations.find_by(user: users(:bartek))
    assert_equal "reserved", bartek_cp.status
  end

  test "DELETE promuje na sub-evencie tę samą osobę co na kampanii, nie pierwszą z sub-event waitlisty" do
    @campaign.update!(capacity: 3)
    # Sub cap 2 = pełny po alice + bobie, więc charlie i dave lądują na jego
    # waitliście (przy wolnych slotach waitlister kampanii od razu łapie slot).
    @sub.update!(capacity: 2)

    alice   = users(:ala)
    bob     = users(:bartek)
    charlie = users(:cezary)
    dave    = users(:dominika)

    CampaignParticipation.create!(event_campaign: @campaign, user: alice,   status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: @campaign, user: bob,     status: :confirmed, position: 2)
    cp_charlie = CampaignParticipation.create!(event_campaign: @campaign, user: charlie, status: :waitlist, position: 1)
    CampaignParticipation.create!(event_campaign: @campaign, user: dave,    status: :waitlist,  position: 2)

    # Swap sub-event waitlist order so dave is ahead of charlie (different from campaign)
    @sub.participations.find_by(user: dave).update_columns(position: 1)
    @sub.participations.find_by(user: charlie).update_columns(position: 2)

    sign_in_as(bob)
    delete event_campaign_campaign_participation_path(@campaign)

    cp_charlie.reload
    assert_equal "confirmed", cp_charlie.status, "charlie awansował na kampanii"

    sub_charlie = @sub.participations.find_by(user: charlie)
    sub_dave    = @sub.participations.find_by(user: dave)
    assert_equal "confirmed", sub_charlie.reload.status,
      "charlie (promowany na kampanii) powinien awansować na sub-evencie, nie dave (pierwszy na sub-event waitlist)"
    assert_equal "waitlist", sub_dave.reload.status,
      "dave powinien zostać na waitliście sub-eventu"
  end

  test "kampanijny waitlister dostaje confirmed na sub-evencie, gdy są wolne miejsca" do
    @campaign.update!(capacity: 2)
    @sub.update!(capacity: 4)

    alice = users(:ala)
    bob   = users(:bartek)
    dave  = users(:dominika)

    CampaignParticipation.create!(event_campaign: @campaign, user: alice, status: :confirmed, position: 1)

    sign_in_as(bob)
    post event_campaign_campaign_participation_path(@campaign)

    bob_cp = @campaign.campaign_participations.find_by(user: bob)
    assert_equal "confirmed", bob_cp.status, "bob confirmed na kampanii (2. slot z 2)"

    bob_sub = @sub.participations.find_by(user: bob)
    assert_equal "confirmed", bob_sub.status, "bob confirmed na sub-evencie (kampanijny confirmed)"

    sign_in_as(dave)
    post event_campaign_campaign_participation_path(@campaign)

    dave_cp = @campaign.campaign_participations.find_by(user: dave)
    assert_equal "waitlist", dave_cp.status, "dave waitlist na kampanii (capacity 2 pełna)"

    dave_sub = @sub.participations.find_by(user: dave)
    assert_equal "confirmed", dave_sub.status,
      "dave (waitlister kampanii) łapie wolny slot sub-eventu"
    assert_equal [ alice.id, bob.id, dave.id ],
                 @sub.participations.confirmed.order(:position).pluck(:user_id),
                 "dave dokłada się na końcu — bez przetasowania"
  end

  test "promocja na kampanii (waitlist→confirmed) kaskaduje na sub-eventy" do
    @campaign.update!(capacity: 2)
    @sub.update!(capacity: 3)

    alice   = users(:ala)
    bob     = users(:bartek)
    charlie = users(:cezary)

    CampaignParticipation.create!(event_campaign: @campaign, user: alice,   status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: @campaign, user: bob,     status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: @campaign, user: charlie, status: :waitlist,  position: 1)

    sign_in_as(bob)
    delete event_campaign_campaign_participation_path(@campaign)

    charlie_sub = @sub.participations.find_by(user: charlie)
    assert_equal "confirmed", charlie_sub.reload.status,
      "charlie promowany na kampanii powinien być promowany na sub-evencie"
  end

  test "endpointy wymagają zalogowania" do
    %i[post delete].each do |verb|
      send(verb, event_campaign_campaign_participation_path(@campaign))
      assert_redirected_to login_path
    end
  end
end
