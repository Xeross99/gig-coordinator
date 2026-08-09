require "test_helper"

# Kompleksowy test synchronizacji rosteru kampanii ↔ sub-eventów.
# Weryfikuje pełny cykl życia: tworzenie → zapisy → edycja capacity →
# promocje/degradacje → historia — i sprawdza, że sub-eventy zawsze
# odzwierciedlają primary roster kampanii.
class CampaignRosterSyncTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @host = hosts(:jan)
    @ala      = users(:ala)
    @bartek   = users(:bartek)
    @cezary   = users(:cezary)
    @dominika = users(:dominika)

    @ala.update!(title: :mistrz_piora)
    @bartek.update!(title: :kurnikowy_komendant)
    @cezary.update!(title: :kurnikowy_gangster)
    @dominika.update!(title: :kurzy_pacholek)
  end

  test "pełny cykl: tworzenie → zapisy → capacity up/down → historia kampanii i sub-eventów" do
    # ================================================================
    # 1. Mistrz tworzy kampanię (capacity=4) z 1 sub-eventem (capacity=4)
    # ================================================================
    sign_in_as(@ala)
    sub_date = 5.days.from_now.to_date.iso8601

    post event_campaigns_path, params: {
      event_campaign: {
        name: "Sync test", host_id: @host.id, capacity: 4,
        events_attributes: [
          { name: "Łapanie pon", event_date: sub_date,
            start_hour: 17, start_minute: 0,
            duration_hours: 2, duration_minutes: 0,
            pay_per_person: 120, capacity: 4 }
        ]
      }
    }
    campaign = EventCampaign.last
    sub = campaign.events.first
    assert_equal 4, campaign.capacity
    assert_equal 4, sub.capacity

    # Ala (mistrz) dostała rezerwację na kampanię
    ala_cp = campaign.campaign_participations.find_by(user: @ala)
    assert_equal "reserved", ala_cp.status
    assert ala_cp.reserved_until.present?

    # Historia kampanii: 1 wpis (utworzenie) + 1 (rezerwacja mistrza)
    get history_event_campaign_path(campaign)
    assert_response :success
    history_events = CampaignParticipationEvent.joins(:campaign_participation)
                       .where(campaign_participations: { event_campaign_id: campaign.id })
    assert_equal 1, history_events.where(event_type: "reserved").count

    # ================================================================
    # 2. Ala akceptuje rezerwację → confirmed na kampanii + sub-eventach
    # ================================================================
    post accept_event_campaign_campaign_participation_path(campaign)
    ala_cp.reload
    assert_equal "confirmed", ala_cp.status

    ala_sub = sub.participations.find_by(user: @ala)
    assert_equal "confirmed", ala_sub.status, "mistrz po akceptacji powinien być confirmed na sub-evencie"

    # Historia: reserved + accepted
    assert_equal 1, history_events.reload.where(event_type: "accepted").count

    # ================================================================
    # 3. Bartek, Cezary, Dominika dołączają do kampanii
    # ================================================================
    delete session_path

    # Bartek → confirmed (2/4)
    sign_in_as(@bartek)
    post event_campaign_campaign_participation_path(campaign)
    bartek_cp = campaign.campaign_participations.find_by(user: @bartek)
    assert_equal "confirmed", bartek_cp.status
    assert_equal "confirmed", sub.participations.find_by(user: @bartek).status,
      "kampanijny confirmed powinien być confirmed na sub-evencie"

    # Cezary → confirmed (3/4)
    sign_in_as(@cezary)
    post event_campaign_campaign_participation_path(campaign)
    cezary_cp = campaign.campaign_participations.find_by(user: @cezary)
    assert_equal "confirmed", cezary_cp.status
    assert_equal "confirmed", sub.participations.find_by(user: @cezary).status

    # Dominika → confirmed (4/4)
    sign_in_as(@dominika)
    post event_campaign_campaign_participation_path(campaign)
    dominika_cp = campaign.campaign_participations.find_by(user: @dominika)
    assert_equal "confirmed", dominika_cp.status
    assert_equal "confirmed", sub.participations.find_by(user: @dominika).status

    # Kampania pełna
    assert_equal 4, campaign.campaign_participations.confirmed.count
    assert_equal 4, campaign.campaign_participations.holding_slot.count

    # Sub-event też pełny z tymi samymi osobami
    assert_equal 4, sub.participations.confirmed.count
    sub_confirmed_ids = sub.participations.confirmed.order(:position).pluck(:user_id)
    campaign_confirmed_ids = campaign.campaign_participations.confirmed.order(:position).pluck(:user_id)
    assert_equal campaign_confirmed_ids, sub_confirmed_ids,
      "sub-event confirmed powinien mieć te same osoby co kampania"

    # Historia: 4× joined (bartek, cezary, dominika) + 1 reserved + 1 accepted
    assert_equal 3, history_events.reload.where(event_type: "joined").count

    # ================================================================
    # 4. Capacity UP: 4 → 5. Nikt na waitlistie → slot zostaje pusty
    # ================================================================
    delete session_path
    sign_in_as(@ala)
    patch event_campaign_path(campaign), params: {
      event_campaign: { capacity: 5 }
    }
    assert_redirected_to event_campaign_path(campaign)
    campaign.reload
    assert_equal 5, campaign.capacity
    assert_equal 4, campaign.campaign_participations.confirmed.count, "bez waitlisty nie ma kogo promować"

    # Historia edycji: wpis o zmianie capacity
    change = campaign.changes_log.find_by(field: "capacity")
    assert_equal "4", change.previous_value
    assert_equal "5", change.new_value
    assert_equal @ala.id, change.user_id

    # ================================================================
    # 5. Nowy user (bartek wypisał się i wrócił — symulujemy nowego waitlistera)
    # Bartek wypisuje się z kampanii → 3/5 confirmed
    # ================================================================
    delete session_path
    sign_in_as(@bartek)
    delete event_campaign_campaign_participation_path(campaign)
    bartek_cp.reload
    assert_equal "cancelled", bartek_cp.status
    assert_equal "cancelled", sub.participations.find_by(user: @bartek).reload.status,
      "cancel z kampanii powinien kaskadować na sub-event"

    # Historia: cancelled
    assert_equal 1, history_events.reload.where(event_type: "cancelled")
                                  .joins(:campaign_participation)
                                  .where(campaign_participations: { user_id: @bartek.id }).count

    # Bartek wraca → confirmed (4. slot z 5)
    post event_campaign_campaign_participation_path(campaign)
    bartek_cp.reload
    assert_equal "confirmed", bartek_cp.status
    assert_equal "confirmed", sub.participations.find_by(user: @bartek).reload.status

    # ================================================================
    # 6. Capacity DOWN: 5 → 3. Overflow: 4 confirmed - 3 capacity = 1 degradowany
    # ================================================================
    delete session_path
    sign_in_as(@ala)
    patch event_campaign_path(campaign), params: {
      event_campaign: { capacity: 3 }
    }
    assert_redirected_to event_campaign_path(campaign)
    campaign.reload
    assert_equal 3, campaign.capacity
    assert_equal 3, campaign.campaign_participations.confirmed.count, "1 osoba spadła na waitlist"
    assert_equal 1, campaign.campaign_participations.waitlist.count

    # Sprawdź kto spadł — ostatni wg position
    waitlisted = campaign.campaign_participations.waitlist.order(:position).pluck(:user_id)
    assert_equal 1, waitlisted.size
    demoted_user = User.find(waitlisted.first)

    # Demoted user powinien być w waitlist na sub-evencie... lub confirmed
    # (demote_overflow działa na kampanii, sub-event nie jest automatycznie degradowany)
    # Ale invariant: confirmed na kampanii → confirmed na sub (jeśli jest slot)

    # Ci co zostali confirmed na kampanii powinni być confirmed na sub-evencie
    campaign_confirmed = campaign.campaign_participations.confirmed.pluck(:user_id).to_set
    sub.participations.confirmed.each do |sp|
      next if sp.user_id == demoted_user.id
      assert campaign_confirmed.include?(sp.user_id),
        "#{sp.user.display_name} confirmed na sub-evencie ale nie na kampanii"
    end

    # Historia: capacity zmieniona 5→3
    cap_changes = campaign.changes_log.where(field: "capacity").order(:created_at)
    assert_equal 2, cap_changes.count
    assert_equal "5", cap_changes.last.previous_value
    assert_equal "3", cap_changes.last.new_value

    # ================================================================
    # 7. Capacity UP: 3 → 4. Waitlister powinien awansować
    # ================================================================
    patch event_campaign_path(campaign), params: {
      event_campaign: { capacity: 4 }
    }
    assert_redirected_to event_campaign_path(campaign)
    campaign.reload
    assert_equal 4, campaign.capacity
    assert_equal 4, campaign.campaign_participations.confirmed.count, "waitlister powinien awansować po zwiększeniu capacity"
    assert_equal 0, campaign.campaign_participations.waitlist.count

    # Zdegradowany user wrócił na confirmed
    demoted_cp = campaign.campaign_participations.find_by(user: demoted_user)
    assert_equal "confirmed", demoted_cp.status

    # I powinien być confirmed na sub-evencie (was_promoted kaskaduje)
    demoted_sub = sub.participations.find_by(user: demoted_user)
    assert_equal "confirmed", demoted_sub.reload.status,
      "user promowany na kampanii powinien być promowany na sub-evencie"

    # Historia: promoted
    assert history_events.reload.where(event_type: "promoted").exists?,
      "historia powinna mieć wpis o promocji"

    # ================================================================
    # 8. Nowy sub-event dodany później — seeder kopiuje z primary rostera
    # ================================================================
    sub2 = Event.create!(
      host: @host, event_campaign: campaign, name: "Łapanie śr",
      scheduled_at: 7.days.from_now, ends_at: 7.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )

    # Mistrz dostaje niezależną rezerwację (seed_reservations), reszta → confirmed z seedera
    sub2_active_ids = sub2.participations.where.not(status: :cancelled).pluck(:user_id).to_set
    campaign.campaign_participations.confirmed.each do |cp|
      assert sub2_active_ids.include?(cp.user_id),
        "#{cp.user.display_name} confirmed na kampanii powinien być na nowym sub-evencie"
    end

    # Nie-mistrz confirmed na kampanii → confirmed na sub2
    non_mistrz_confirmed = campaign.campaign_participations.confirmed
                                    .joins(:user).where.not(users: { title: User.titles[:mistrz_piora] })
                                    .pluck(:user_id).to_set
    sub2_confirmed_ids = sub2.participations.confirmed.pluck(:user_id).to_set
    non_mistrz_confirmed.each do |uid|
      assert sub2_confirmed_ids.include?(uid),
        "#{User.find(uid).display_name} (nie-mistrz) confirmed na kampanii ale nie confirmed na sub2"
    end

    # ================================================================
    # 9. Finalna weryfikacja: sub1 ma tych samych confirmed co kampania
    #    (sub2 ma mistrza jako reserved — niezależna rezerwacja)
    # ================================================================
    expected_ids = campaign.campaign_participations.confirmed.pluck(:user_id).to_set

    sub_confirmed = sub.participations.confirmed.pluck(:user_id).to_set
    expected_ids.each do |uid|
      assert sub_confirmed.include?(uid),
        "#{User.find(uid).display_name} confirmed na kampanii ale brak na #{sub.name}"
    end
  end

  test "waitlister na kampanii łapie wolne sloty sub-eventu, gdy jego capacity na to pozwala" do
    sign_in_as(@ala)

    # Kampania capacity=2, sub-event capacity=10 (dużo miejsca)
    campaign = EventCampaign.create!(host: @host, name: "Waitlist test", capacity: 2, creator: @ala)
    campaign.campaign_participations.destroy_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub duży",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 10
    )
    sub.participations.destroy_all

    # Ala i Bartek confirmed na kampanii (2/2)
    CampaignParticipation.create!(event_campaign: campaign, user: @ala, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @bartek, status: :confirmed, position: 2)

    # Cezary i Dominika na waitliście kampanii
    CampaignParticipation.create!(event_campaign: campaign, user: @cezary, status: :waitlist, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @dominika, status: :waitlist, position: 2)

    # Sub-event ma capacity 10 — waitlisterzy kampanii dostają wolne sloty
    cezary_sub = sub.participations.find_by(user: @cezary)
    dominika_sub = sub.participations.find_by(user: @dominika)

    assert_equal "confirmed", cezary_sub.status,
      "kampanijny waitlister łapie wolny slot sub-eventu"
    assert_equal "confirmed", dominika_sub.status

    # Confirmed na kampanii → confirmed na sub-evencie, przed waitlisterami
    assert_equal "confirmed", sub.participations.find_by(user: @ala).status
    assert_equal "confirmed", sub.participations.find_by(user: @bartek).status
    assert_equal [ @ala.id, @bartek.id, @cezary.id, @dominika.id ],
                 sub.participations.confirmed.order(:position).pluck(:user_id),
                 "kolejność: primary confirmed, potem waitlisterzy po pozycji"
  end

  test "cancel confirmed z kampanii → promuje tego samego usera na sub-evencie co na kampanii" do
    campaign = EventCampaign.create!(host: @host, name: "Cancel sync", capacity: 3, creator: @ala)
    campaign.campaign_participations.destroy_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 3
    )
    sub.participations.destroy_all

    # Buduj roster: ala, bartek, cezary confirmed; dominika waitlist
    CampaignParticipation.create!(event_campaign: campaign, user: @ala, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @bartek, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @cezary, status: :confirmed, position: 3)
    CampaignParticipation.create!(event_campaign: campaign, user: @dominika, status: :waitlist, position: 1)

    # Zamień kolejność waitlisty na sub-evencie (dominika poniżej cezary'ego)
    # Upewnij się że sub-event nie ma jeszcze dominiki na waitliście w złej pozycji

    # Weryfikuj stan wyjściowy
    assert_equal 3, sub.participations.confirmed.count
    assert_equal 1, sub.participations.waitlist.count
    assert_equal "waitlist", sub.participations.find_by(user: @dominika).status

    # Bartek wypisuje się z kampanii
    sign_in_as(@bartek)
    delete event_campaign_campaign_participation_path(campaign)

    # Kampania: bartek cancelled, dominika promowana (waitlist→confirmed)
    dominika_cp = campaign.campaign_participations.find_by(user: @dominika)
    assert_equal "confirmed", dominika_cp.reload.status

    # Sub-event: bartek cancelled, dominika promowana (nie ktoś inny!)
    assert_equal "cancelled", sub.participations.find_by(user: @bartek).reload.status
    assert_equal "confirmed", sub.participations.find_by(user: @dominika).reload.status,
      "ta sama osoba promowana na kampanii powinna być promowana na sub-evencie"

    # Łącznie 3 confirmed na sub-evencie (ala, cezary, dominika)
    assert_equal 3, sub.participations.confirmed.count
    sub_confirmed = sub.participations.confirmed.pluck(:user_id).to_set
    assert sub_confirmed.include?(@ala.id)
    assert sub_confirmed.include?(@cezary.id)
    assert sub_confirmed.include?(@dominika.id)
  end

  test "historia kampanii rejestruje pełną sekwencję: create → join → cancel → promote → capacity change" do
    sign_in_as(@ala)
    sub_date = 5.days.from_now.to_date.iso8601

    post event_campaigns_path, params: {
      event_campaign: {
        name: "Historia test", host_id: @host.id, capacity: 2,
        events_attributes: [
          { name: "Sub", event_date: sub_date,
            start_hour: 17, start_minute: 0,
            duration_hours: 2, duration_minutes: 0,
            pay_per_person: 100, capacity: 4 }
        ]
      }
    }
    campaign = EventCampaign.last

    # Ala akceptuje rezerwację
    post accept_event_campaign_campaign_participation_path(campaign)

    # Bartek dołącza (confirmed 2/2)
    sign_in_as(@bartek)
    post event_campaign_campaign_participation_path(campaign)

    # Cezary dołącza (waitlist)
    sign_in_as(@cezary)
    post event_campaign_campaign_participation_path(campaign)

    # Bartek wypisuje się → Cezary awansuje
    sign_in_as(@bartek)
    delete event_campaign_campaign_participation_path(campaign)

    # Ala zmienia capacity 2→3
    sign_in_as(@ala)
    patch event_campaign_path(campaign), params: { event_campaign: { capacity: 3 } }

    # Sprawdź historię
    get history_event_campaign_path(campaign)
    assert_response :success

    events = CampaignParticipationEvent.joins(:campaign_participation)
               .where(campaign_participations: { event_campaign_id: campaign.id })
               .pluck(:event_type)

    assert_includes events, "reserved",  "brak wpisu o rezerwacji mistrza"
    assert_includes events, "accepted",  "brak wpisu o akceptacji"
    assert_includes events, "joined",    "brak wpisu o dołączeniu"
    assert_includes events, "joined_waitlist", "brak wpisu o dołączeniu do waitlisty"
    assert_includes events, "cancelled", "brak wpisu o wypisaniu"
    assert_includes events, "promoted",  "brak wpisu o promocji"

    # Historia edycji capacity
    cap_change = campaign.changes_log.find_by(field: "capacity")
    assert_not_nil cap_change
    assert_equal "2", cap_change.previous_value
    assert_equal "3", cap_change.new_value
  end

  test "sub-event z mniejszym capacity niż kampania: overflow na waitlistę sub-eventu" do
    # Żaden user nie jest mistrz_piora — unikamy seed_reservations na sub-evencie
    @ala.update!(title: :kurnikowy_komendant)

    campaign = EventCampaign.create!(host: @host, name: "Overflow test", capacity: 4, creator: @ala)
    campaign.campaign_participations.destroy_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    CampaignParticipation.create!(event_campaign: campaign, user: @ala, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @bartek, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @cezary, status: :confirmed, position: 3)
    CampaignParticipation.create!(event_campaign: campaign, user: @dominika, status: :confirmed, position: 4)

    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Mały sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 2
    )

    assert_equal 2, sub.participations.confirmed.count,
      "sub-event z capacity=2 powinien mieć max 2 confirmed"
    assert_equal 2, sub.participations.waitlist.count,
      "pozostali 2 kampanijni confirmed powinni być na waitliście sub-eventu"

    confirmed_ids = sub.participations.confirmed.order(:position).pluck(:user_id)
    assert_equal [ @ala.id, @bartek.id ], confirmed_ids,
      "pierwsi 2 wg position z kampanii powinni być confirmed na sub-evencie"

    waitlist_ids = sub.participations.waitlist.order(:position).pluck(:user_id)
    assert_equal [ @cezary.id, @dominika.id ], waitlist_ids,
      "ostatni 2 wg position z kampanii powinni być na waitliście sub-eventu"
  end

  test "capacity down: ostatni confirmed trafia na pozycję 1 rezerwy, istniejąca rezerwa przesuwa się w dół" do
    campaign = EventCampaign.create!(host: @host, name: "Demote pos test", capacity: 5, creator: @ala)
    campaign.campaign_participations.destroy_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    sub = Event.create!(
      host: @host, event_campaign: campaign, name: "Sub",
      scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 5
    )
    sub.participations.destroy_all

    # 4 confirmed + 1 waitlister (dominika)
    CampaignParticipation.create!(event_campaign: campaign, user: @ala, status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: @bartek, status: :confirmed, position: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: @cezary, status: :confirmed, position: 3)

    # Dominika jako istniejący waitlister na pozycji 1
    CampaignParticipation.create!(event_campaign: campaign, user: @dominika, status: :waitlist, position: 1)

    # Capacity 5→2: cezary (pos=3, ostatni) spada na waitlist
    campaign.edited_by = @ala
    campaign.update!(capacity: 2)

    # Kampania: 2 confirmed (ala, bartek), 2 waitlist
    assert_equal 2, campaign.campaign_participations.confirmed.count
    assert_equal 2, campaign.campaign_participations.waitlist.count

    confirmed = campaign.campaign_participations.confirmed.order(:position)
    assert_equal @ala.id,    confirmed.first.user_id, "ala zostaje confirmed (pos=1)"
    assert_equal @bartek.id, confirmed.second.user_id, "bartek zostaje confirmed (pos=2)"

    waitlist = campaign.campaign_participations.waitlist.order(:position)
    assert_equal @cezary.id,   waitlist.first.user_id,
      "cezary (zdegradowany) powinien być na pozycji 1 rezerwy"
    assert_equal 1, waitlist.first.position

    assert_equal @dominika.id, waitlist.second.user_id,
      "dominika (istniejący waitlister) przesunięta na pozycję 2"
    assert_equal 2, waitlist.second.position
  end
end
