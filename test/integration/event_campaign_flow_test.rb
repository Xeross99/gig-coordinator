require "test_helper"

class EventCampaignFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @host = hosts(:jan)
    users(:ala).update!(title:     :mistrz_piora)
    users(:bartek).update!(title:  :kurnikowy_gangster)
    users(:cezary).update!(title:  :kurzy_pacholek)
    users(:dominika).update!(title: :zoltodziob)
  end

  test "tworzenie cyklu z sub-eventami, zapis na kampanię, niezależny zapis na sub-event" do
    sign_in_as(users(:ala))

    sub1_date = 5.days.from_now.to_date.iso8601
    sub2_date = 12.days.from_now.to_date.iso8601

    assert_difference -> { EventCampaign.count } => +1, -> { Event.count } => +2 do
      post event_campaigns_path, params: {
        event_campaign: {
          name: "Czerwiec 2026", host_id: @host.id, capacity: 4,
          events_attributes: [
            { name: "Łapanie 1", event_date: sub1_date,
              start_hour: 7, start_minute: 0, duration_hours: 2, duration_minutes: 0,
              pay_per_person: 100, capacity: 4 },
            { name: "Łapanie 2", event_date: sub2_date,
              start_hour: 7, start_minute: 0, duration_hours: 2, duration_minutes: 0,
              pay_per_person: 150, capacity: 4 }
          ]
        }
      }
    end
    campaign = EventCampaign.last

    ala_cp = campaign.campaign_participations.find_by(user: users(:ala))
    assert_equal "reserved", ala_cp.status, "mistrz dostaje rezerwację na primary"

    post accept_event_campaign_campaign_participation_path(campaign)
    ala_cp.reload
    assert_equal "confirmed", ala_cp.status

    # Sub-eventy mają niezależne rezerwacje (seed_reservations per event)
    campaign.events.each do |sub|
      sub_p = sub.participations.find_by(user: users(:ala))
      assert sub_p.present?, "ala ma participation na sub-evencie (z seeder lub reservation)"
    end
  end

  test "bezpośredni zapis na sub-event jest dozwolony (bez redirectu na kampanię)" do
    sign_in_as(users(:bartek))
    campaign = EventCampaign.create!(host: @host, name: "Test", capacity: 4)
    campaign.campaign_participations.destroy_all
    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )
    sub.participations.destroy_all

    assert_difference -> { sub.participations.count }, +1 do
      post event_participation_path(sub)
    end
    assert_equal "confirmed", sub.participations.find_by(user: users(:bartek)).status
  end

  test "wypisanie z kampanii canceluje sub-eventy" do
    sign_in_as(users(:bartek))
    campaign = EventCampaign.create!(host: @host, name: "Test", capacity: 4)
    campaign.campaign_participations.destroy_all
    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )
    sub.participations.destroy_all

    post event_campaign_campaign_participation_path(campaign)
    post event_participation_path(sub)

    assert_equal "confirmed", campaign.campaign_participations.find_by(user: users(:bartek)).status
    assert_equal "confirmed", sub.participations.find_by(user: users(:bartek)).status

    delete event_campaign_campaign_participation_path(campaign)

    assert_equal "cancelled", campaign.campaign_participations.find_by(user: users(:bartek)).reload.status
    assert_equal "cancelled", sub.participations.find_by(user: users(:bartek)).reload.status
  end

  test "wypisanie z sub-eventu nie wpływa na primary roster kampanii" do
    sign_in_as(users(:bartek))
    campaign = EventCampaign.create!(host: @host, name: "Test", capacity: 4)
    campaign.campaign_participations.destroy_all
    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )
    sub.participations.destroy_all

    post event_campaign_campaign_participation_path(campaign)
    post event_participation_path(sub)
    delete event_participation_path(sub)

    assert_equal "cancelled", sub.participations.find_by(user: users(:bartek)).reload.status
    assert_equal "confirmed", campaign.campaign_participations.find_by(user: users(:bartek)).reload.status,
                 "primary roster untouched"
  end

  test "sub-event utworzony PO primary rosterze dziedziczy skład z seedera" do
    campaign = EventCampaign.create!(host: @host, name: "Cykl późny sub", capacity: 4)
    campaign.campaign_participations.destroy_all
    CampaignParticipation.create!(event_campaign: campaign, user: users(:bartek),
                                  status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: users(:cezary),
                                  status: :confirmed, position: 2)

    late_sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Późny",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )

    assert_equal 2, late_sub.participations.confirmed.count
    confirmed_users = late_sub.participations.confirmed.map(&:user_id).to_set
    assert_equal Set[users(:bartek).id, users(:cezary).id], confirmed_users
  end

  test "sub-event z mniejszym capacity pakuje nadmiarowych na waitlistę" do
    campaign = EventCampaign.create!(host: @host, name: "Cykl mała pojemność", capacity: 5)
    campaign.campaign_participations.destroy_all
    [ users(:ala), users(:bartek), users(:cezary), users(:dominika) ].each_with_index do |user, idx|
      CampaignParticipation.create!(event_campaign: campaign, user: user,
                                    status: :confirmed, position: idx + 1)
    end

    # capacity=3, primary ma 4 confirmed → 3 confirmed, 1 waitlist
    small_sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Mały sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 3
    )

    assert_equal 3, small_sub.participations.confirmed.count
    assert_equal 0, small_sub.participations.reserved.count
    assert_equal "waitlist", small_sub.participations.find_by(user: users(:dominika)).status
  end

  test "blokada hosta uniemożliwia zapis na cykl ALE nie kasuje istniejącego uczestnictwa" do
    sign_in_as(users(:bartek))
    campaign = EventCampaign.create!(host: @host, name: "Cykl block", capacity: 4)
    campaign.campaign_participations.destroy_all

    post event_campaign_campaign_participation_path(campaign)
    cp = campaign.campaign_participations.find_by(user: users(:bartek))
    assert_equal "confirmed", cp.status

    HostBlock.create!(user: users(:bartek), host: @host)

    delete event_campaign_campaign_participation_path(campaign)
    post event_campaign_campaign_participation_path(campaign)
    cp.reload
    assert_equal "cancelled", cp.status
  end

  test "started sub-event nie jest cancelowany przy wypisaniu z kampanii" do
    sign_in_as(users(:bartek))
    campaign = EventCampaign.create!(host: @host, name: "Cykl frozen", capacity: 4)
    campaign.campaign_participations.destroy_all

    started_sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Już ruszył",
      scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now,
      pay_per_person: 100, capacity: 4
    )
    started_sub.participations.destroy_all
    Participation.create!(event: started_sub, user: users(:bartek), status: :confirmed, position: 1)

    post event_campaign_campaign_participation_path(campaign)

    delete event_campaign_campaign_participation_path(campaign)

    assert_equal "confirmed", started_sub.participations.find_by(user: users(:bartek)).reload.status,
                 "started sub-event untouched"
  end

  test "POST /kampanie wymaga uprawnień event_creator" do
    users(:ala).update!(title: :kurzy_pacholek)
    sign_in_as(users(:ala))

    assert_no_difference -> { EventCampaign.count } do
      post event_campaigns_path, params: {
        event_campaign: { name: "Próba", host_id: @host.id, capacity: 4 }
      }
    end
    assert_redirected_to root_path
  end

  test "nowe łapanie w rzucie kopiuje stały skład 1:1 — ci sami ludzie, ta sama kolejność" do
    ala     = users(:ala)
    bartek  = users(:bartek)
    cezary  = users(:cezary)
    dominika = users(:dominika)

    # 1. Stwórz rzut (capacity=3) i wyczyść auto-seed
    campaign = EventCampaign.create!(host: @host, name: "Rzut kopiowania", capacity: 3)
    campaign.campaign_participations.destroy_all

    # 2. Osoby zapisują się na kampanię przez HTTP — w konkretnej kolejności
    sign_in_as(bartek)
    post event_campaign_campaign_participation_path(campaign)

    delete session_path
    sign_in_as(cezary)
    post event_campaign_campaign_participation_path(campaign)

    delete session_path
    sign_in_as(dominika)
    post event_campaign_campaign_participation_path(campaign)

    # Bartek, Cezary, Dominika → confirmed (capacity=3). Ala jeszcze nie.
    delete session_path
    sign_in_as(ala)
    post event_campaign_campaign_participation_path(campaign)
    # Ala → waitlist (pełne)

    # Sprawdź primary roster
    primary_confirmed = campaign.campaign_participations.reload.confirmed.order(:position)
    primary_waitlist   = campaign.campaign_participations.waitlist.order(:position)

    assert_equal 3, primary_confirmed.count
    assert_equal 1, primary_waitlist.count
    confirmed_ids_ordered = primary_confirmed.pluck(:user_id)
    waitlist_ids_ordered  = primary_waitlist.pluck(:user_id)
    assert_equal [ bartek.id, cezary.id, dominika.id ], confirmed_ids_ordered
    assert_equal [ ala.id ], waitlist_ids_ordered

    # 3. Dodaj nowe łapanie z capacity=3 (= tyle samo co confirmed na kampanii)
    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Nowe łapanie",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 120, capacity: 3
    )

    sub_confirmed = sub.participations.confirmed.order(:position).pluck(:user_id)
    sub_waitlist  = sub.participations.waitlist.order(:position).pluck(:user_id)

    # Główna lista — te same osoby w tej samej kolejności
    assert_equal confirmed_ids_ordered, sub_confirmed,
                 "główna lista sub-eventu = stały skład kampanii 1:1"

    # Rezerwa — te same osoby co rezerwa kampanii, ta sama kolejność
    assert_equal waitlist_ids_ordered, sub_waitlist,
                 "rezerwa sub-eventu = rezerwa kampanii 1:1"

    # 4. Dodaj drugie łapanie z MNIEJSZYM capacity (2 < 3 confirmed)
    #    → pierwsi 2 confirmed, trzeci + rezerwa kampanii na waitlist sub-eventu.
    sub2 = Event.create!(
      host: @host, event_campaign: campaign, name: "Mniejsze łapanie",
      scheduled_at: 6.days.from_now, ends_at: 6.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 2
    )

    sub2_confirmed = sub2.participations.confirmed.order(:position).pluck(:user_id)
    sub2_waitlist  = sub2.participations.waitlist.order(:position).pluck(:user_id)

    # Główna lista — pierwsi 2 z primary confirmed (ta sama kolejność)
    assert_equal confirmed_ids_ordered.first(2), sub2_confirmed,
                 "mniejsza capacity → top-2 z primary confirmed, ta sama kolejność"

    # Rezerwa — nadmiarowy confirmed (dominika) + rezerwa kampanii (ala)
    assert_equal [ dominika.id, ala.id ], sub2_waitlist,
                 "nadmiarowy confirmed + rezerwa kampanii → waitlist sub-eventu, w tej kolejności"
  end

  test "DELETE /kampanie/:id wymaga uprawnień manage" do
    campaign = EventCampaign.create!(host: @host, name: "Czyj?", capacity: 4, creator: users(:ala))
    users(:bartek).update!(title: :mistrz_piora)
    sign_in_as(users(:bartek))

    assert_difference -> { EventCampaign.count }, -1 do
      delete event_campaign_path(campaign)
    end
  end
end
