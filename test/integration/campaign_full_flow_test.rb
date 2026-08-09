require "test_helper"

# Kompleksowy test flow kampanii po usunięciu kaskady:
# Tworzenie kampanii → rezerwacje mistrza → akceptacja → zapis kolejnych osób →
# wypisanie → promocja z waitlisty → historia → nowy sub-event dodany później.
class CampaignFullFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @host = hosts(:jan)
    @ala     = users(:ala)
    @bartek  = users(:bartek)
    @cezary  = users(:cezary)
    @dominika = users(:dominika)

    @ala.update!(title: :mistrz_piora)
    @bartek.update!(title: :kurnikowy_gangster)
    @cezary.update!(title: :kurzy_pacholek)
    @dominika.update!(title: :kurzy_pacholek)
  end

  test "pełny flow kampanii: tworzenie → rezerwacja mistrza → zapisy → waitlist → wypisanie → promo → historia" do
    # ---- 1. Mistrz tworzy kampanię z 1 sub-eventem (capacity primary=3, sub capacity=3) ----
    sign_in_as(@ala)
    sub_date = 5.days.from_now.to_date.iso8601

    post event_campaigns_path, params: {
      event_campaign: {
        name: "Seria testowa", host_id: @host.id, capacity: 3,
        events_attributes: [
          { name: "Łapanie pon", event_date: sub_date,
            start_hour: 7, start_minute: 0, duration_hours: 2, duration_minutes: 0,
            pay_per_person: 120, capacity: 3 }
        ]
      }
    }
    campaign = EventCampaign.last
    sub = campaign.events.first
    assert_equal "Seria testowa", campaign.name
    assert_equal 3, campaign.capacity

    # ---- 2. Ala (mistrz) dostaje rezerwację na kampanię (2.5h) ----
    ala_cp = campaign.campaign_participations.find_by(user: @ala)
    assert_equal "reserved", ala_cp.status
    assert ala_cp.reserved_until.present?

    # Sub-event NIE ma niezależnej rezerwacji — seed_reservations pomija sub-eventy
    assert_nil sub.participations.find_by(user: @ala),
               "sub-event nie seeduje rezerwacji — mistrz trafi tu po akceptacji kampanii"

    # ---- 3. Historia kampanii — ma wpis „rezerwacja" ----
    get history_event_campaign_path(campaign)
    assert_response :success

    # ---- 4. Ala akceptuje rezerwację na kampanię ----
    post accept_event_campaign_campaign_participation_path(campaign)
    ala_cp.reload
    assert_equal "confirmed", ala_cp.status
    assert_nil ala_cp.reserved_until
    assert_equal 1, ala_cp.position

    # ---- 5. Bartek zapisuje się na kampanię ----
    delete session_path
    sign_in_as(@bartek)
    post event_campaign_campaign_participation_path(campaign)
    bartek_cp = campaign.campaign_participations.find_by(user: @bartek)
    assert_equal "confirmed", bartek_cp.status
    assert_equal 2, bartek_cp.position

    # ---- 6. Cezary zapisuje się na kampanię — confirmed (3. slot) ----
    delete session_path
    sign_in_as(@cezary)
    post event_campaign_campaign_participation_path(campaign)
    cezary_cp = campaign.campaign_participations.find_by(user: @cezary)
    assert_equal "confirmed", cezary_cp.status
    assert_equal 3, cezary_cp.position

    # ---- 7. Dominika zapisuje się — capacity=3 pełna, ląduje na waitlist ----
    delete session_path
    sign_in_as(@dominika)
    post event_campaign_campaign_participation_path(campaign)
    dominika_cp = campaign.campaign_participations.find_by(user: @dominika)
    assert_equal "waitlist", dominika_cp.status

    # ---- 8. Bartek zapisuje się na sub-event bezpośrednio ----
    delete session_path
    sign_in_as(@bartek)
    post event_participation_path(sub)
    bartek_sub_p = sub.participations.find_by(user: @bartek)
    assert_equal "confirmed", bartek_sub_p.status

    # ---- 9. Bartek wypisuje się z kampanii → canceluje też sub-eventy ----
    delete event_campaign_campaign_participation_path(campaign)
    bartek_cp.reload
    assert_equal "cancelled", bartek_cp.status
    bartek_sub_p.reload
    assert_equal "cancelled", bartek_sub_p.status, "wypisanie z kampanii canceluje sub-eventy"

    # ---- 10. Dominika awansuje z waitlisty na kampanię (promocja) ----
    dominika_cp.reload
    assert_equal "confirmed", dominika_cp.status, "promocja z waitlisty"

    # ---- 11. Cezary wypisuje się z kampanii PLUS sub-eventy ----
    delete session_path
    sign_in_as(@cezary)
    post event_participation_path(sub)  # najpierw niech się zapisze na sub
    cezary_sub_p = sub.participations.find_by(user: @cezary)
    assert_equal "confirmed", cezary_sub_p.status

    delete event_campaign_campaign_participation_path(campaign)
    cezary_cp.reload
    assert_equal "cancelled", cezary_cp.status
    cezary_sub_p.reload
    assert_equal "cancelled", cezary_sub_p.status, "wypisanie z kampanii canceluje sub-eventy"

    # ---- 12. Host dodaje nowy sub-event — seeder kopiuje z primary rostera ----
    sub2 = Event.create!(
      host: @host, event_campaign: campaign, name: "Łapanie śr",
      scheduled_at: 7.days.from_now, ends_at: 7.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )

    # Primary roster: ala (confirmed), dominika (confirmed). Seeder kopiuje obie.
    confirmed_on_sub2 = sub2.participations.confirmed.pluck(:user_id).to_set
    assert_includes confirmed_on_sub2, @ala.id, "ala z primary → confirmed na sub2"
    assert_includes confirmed_on_sub2, @dominika.id, "dominika z primary → confirmed na sub2"

    # ---- 13. Historia kampanii — pełna sekwencja event_types ----
    delete session_path
    sign_in_as(@ala)
    get history_event_campaign_path(campaign)
    assert_response :success

    # Sprawdź event_types w CampaignParticipationEvent
    all_events = CampaignParticipationEvent.joins(:campaign_participation)
                   .where(campaign_participations: { event_campaign_id: campaign.id })
                   .order(:created_at)
                   .pluck(:event_type)

    assert_includes all_events, "reserved",  "historia: rezerwacja mistrza"
    assert_includes all_events, "accepted",  "historia: akceptacja rezerwacji"
    assert_includes all_events, "joined",    "historia: dołączenie usera"
    assert_includes all_events, "cancelled", "historia: wypisanie"
    assert_includes all_events, "promoted",  "historia: promocja z waitlisty"
  end

  test "sub-event: mistrz akceptuje kampanię → kaskada na sub-event → kolejni userzy" do
    campaign = EventCampaign.create!(host: @host, name: "Sub flow", capacity: 4)
    campaign.campaign_participations.destroy_all
    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 3
    )

    # Sub-event nie ma niezależnych rezerwacji — seed_reservations pomija sub-eventy
    assert_nil sub.participations.find_by(user: @ala)

    # Ala zapisuje się bezpośrednio na sub-event
    sign_in_as(@ala)
    post event_participation_path(sub)
    assert_equal "confirmed", sub.participations.find_by(user: @ala).status

    # Bartek dołącza bezpośrednio do sub-eventu
    delete session_path
    sign_in_as(@bartek)
    post event_participation_path(sub)
    assert_equal "confirmed", sub.participations.find_by(user: @bartek).status

    # Cezary dołącza — 3. slot
    delete session_path
    sign_in_as(@cezary)
    post event_participation_path(sub)
    assert_equal "confirmed", sub.participations.find_by(user: @cezary).status

    # Dominika — pełny, waitlist
    delete session_path
    sign_in_as(@dominika)
    post event_participation_path(sub)
    assert_equal "waitlist", sub.participations.find_by(user: @dominika).status

    # Bartek wypisuje się — Dominika awansuje
    delete session_path
    sign_in_as(@bartek)
    delete event_participation_path(sub)
    assert_equal "cancelled", sub.participations.find_by(user: @bartek).reload.status
    assert_equal "confirmed", sub.participations.find_by(user: @dominika).reload.status

    # Historia sub-eventu
    sub_history = ParticipationEvent.joins(:participation)
                    .where(participations: { event_id: sub.id })
                    .order(:created_at)
                    .pluck(:event_type)
    assert_includes sub_history, "joined"
    assert_includes sub_history, "cancelled"
    assert_includes sub_history, "promoted"
  end

  test "rezerwacja mistrza: decline → refill zaprasza następnego mistrza" do
    @bartek.update!(title: :mistrz_piora)
    campaign = EventCampaign.create!(host: @host, name: "Decline flow", capacity: 4)
    # Nie czyścimy — seed_on_create dał rezerwacje obu mistrzom

    ala_cp = campaign.campaign_participations.find_by(user: @ala)
    bartek_cp = campaign.campaign_participations.find_by(user: @bartek)
    assert_equal "reserved", ala_cp.status
    assert_equal "reserved", bartek_cp.status

    sign_in_as(@ala)
    post decline_event_campaign_campaign_participation_path(campaign)
    ala_cp.reload
    assert_equal "cancelled", ala_cp.status

    # Bartek nadal ma rezerwację (oba dostali na seed, decline nie zmienia bartka)
    bartek_cp.reload
    assert_equal "reserved", bartek_cp.status
  end

  test "seeder na nowym sub-evencie kopiuje z primary (bez niezależnych rezerwacji)" do
    campaign = EventCampaign.create!(host: @host, name: "Seeder test", capacity: 4)
    campaign.campaign_participations.destroy_all

    CampaignParticipation.create!(event_campaign: campaign, user: @bartek, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @cezary, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @dominika, status: :waitlist, position: 1)

    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Seeded",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )

    # Seeder: bartek + cezary confirmed (z primary).
    confirmed = sub.participations.confirmed.pluck(:user_id).to_set
    assert_includes confirmed, @bartek.id
    assert_includes confirmed, @cezary.id

    # dominika = waitlist na primary, ale sub-event (cap 4) ma wolne sloty →
    # seeder dopakowuje ją na confirmed za primary-confirmed
    assert_includes confirmed, @dominika.id, "waitlister kampanii łapie wolny slot sub-eventu"
    assert_equal [ @bartek.id, @cezary.id, @dominika.id ],
                 sub.participations.confirmed.order(:position).pluck(:user_id),
                 "kolejność: primary confirmed przed waitlisterami"

    # Ala (mistrz) NIE ma rezerwacji — seed_reservations pomija sub-eventy
    assert_nil sub.participations.find_by(user: @ala),
               "sub-event nie seeduje niezależnych rezerwacji"
  end
end
