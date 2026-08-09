require "test_helper"

# Edge-case'y pełnego flow rzutów łapań (kampania + sub-eventy):
# dołączenie na listę główną, wypisanie się z JEDNEGO łapania, kaskady
# anulacji, ponowne dołączenia i seeding nowych sub-eventów.
class CampaignFlowEdgeCasesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @host = hosts(:jan)
  end

  def build_campaign(capacity:, name: "Rzut testowy")
    c = EventCampaign.create!(host: @host, name: name, capacity: capacity)
    # seed_reservations mógł zaprosić fixture'owych mistrzów — czyścimy,
    # testy budują roster jawnie.
    c.campaign_participations.destroy_all
    clear_enqueued_jobs
    c
  end

  def add_sub_event(campaign, name:, capacity:, scheduled_at: 2.days.from_now)
    Event.create!(
      host: @host, event_campaign: campaign, name: name,
      scheduled_at: scheduled_at, ends_at: scheduled_at + 2.hours,
      pay_per_person: 50, capacity: capacity
    )
  end

  def make_user(label)
    User.create!(first_name: label, last_name: "Testowy", email: "flow_#{label.downcase}_#{SecureRandom.hex(3)}@test.example")
  end

  def join_campaign(campaign, user, status:, position:)
    CampaignParticipation.create!(event_campaign: campaign, user: user, status: status, position: position)
  end

  def status_on(event, user)
    event.participations.find_by(user_id: user.id)&.status
  end

  # --- dołączenie na listę główną -------------------------------------------

  test "join na listę główną auto-zapisuje na wszystkie nadchodzące sub-eventy" do
    campaign = build_campaign(capacity: 2)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 2)
    e2 = add_sub_event(campaign, name: "Łapanie 2", capacity: 2, scheduled_at: 3.days.from_now)

    u1 = make_user("Adam")
    join_campaign(campaign, u1, status: :confirmed, position: 1)

    assert_equal "confirmed", status_on(e1, u1)
    assert_equal "confirmed", status_on(e2, u1)
  end

  test "join gdy sub-event jest pełny -> waitlist tylko na tym sub-evencie" do
    campaign = build_campaign(capacity: 3)
    e_small = add_sub_event(campaign, name: "Małe łapanie", capacity: 2)
    e_big   = add_sub_event(campaign, name: "Duże łapanie", capacity: 3, scheduled_at: 3.days.from_now)

    u1, u2, u3 = make_user("A"), make_user("B"), make_user("C")
    join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :confirmed, position: 2)
    join_campaign(campaign, u3, status: :confirmed, position: 3)

    assert_equal "waitlist",  status_on(e_small, u3), "trzeci na małym sub-evencie idzie na rezerwę"
    assert_equal "confirmed", status_on(e_big, u3),   "na dużym mieści się na głównej"
  end

  test "campaign-waitlister łapie wolny slot sub-eventu" do
    campaign = build_campaign(capacity: 1)
    e1 = add_sub_event(campaign, name: "Łapanie", capacity: 4)

    u1, u2 = make_user("A"), make_user("B")
    join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :waitlist,  position: 1)

    assert_equal "confirmed", status_on(e1, u2), "wolne miejsce na sub-evencie idzie do waitlistera kampanii"
    assert_equal [ u1.id, u2.id ], e1.participations.confirmed.order(:position).pluck(:user_id),
                 "primary confirmed zostaje przed waitlisterem"
  end

  test "campaign-waitlister idzie na waitlistę sub-eventu tylko gdy sub-event jest pełny" do
    campaign = build_campaign(capacity: 1)
    e_full = add_sub_event(campaign, name: "Ciasne", capacity: 1)

    u1, u2 = make_user("A"), make_user("B")
    join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :waitlist,  position: 1)

    assert_equal "confirmed", status_on(e_full, u1)
    assert_equal "waitlist",  status_on(e_full, u2)
  end

  test "seeder nowego sub-eventu dopakowuje waitlisterów kampanii w wolne sloty, zachowując kolejność primary" do
    campaign = build_campaign(capacity: 2)
    u1, u2, u3, u4 = make_user("A"), make_user("B"), make_user("C"), make_user("D")
    join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :confirmed, position: 2)
    join_campaign(campaign, u3, status: :waitlist,  position: 1)
    join_campaign(campaign, u4, status: :waitlist,  position: 2)

    e_new = add_sub_event(campaign, name: "Nowy termin", capacity: 3)

    assert_equal [ u1.id, u2.id, u3.id ], e_new.participations.confirmed.order(:position).pluck(:user_id),
                 "confirmed primary wchodzą pierwsi, potem waitlisterzy po pozycji"
    assert_equal [ u4.id ], e_new.participations.waitlist.order(:position).pluck(:user_id),
                 "kto się nie zmieścił, ląduje na waitliście sub-eventu w kolejności primary"
    assert_equal [ 1, 2, 3 ], e_new.participations.confirmed.order(:position).pluck(:position)
  end

  test "po wskoczeniu waitlistera kolejne przeliczenia (wypisanie + promocja) trzymają kolejność" do
    campaign = build_campaign(capacity: 2)
    u1, u2, u3, u4 = make_user("A"), make_user("B"), make_user("C"), make_user("D")
    join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :confirmed, position: 2)
    join_campaign(campaign, u3, status: :waitlist,  position: 1)
    join_campaign(campaign, u4, status: :waitlist,  position: 2)

    e1 = add_sub_event(campaign, name: "Łapanie", capacity: 3)
    assert_equal [ u1.id, u2.id, u3.id ], e1.participations.confirmed.order(:position).pluck(:user_id)
    assert_equal "waitlist", status_on(e1, u4)

    # u2 wypisuje się TYLKO z tego łapania — u4 (najstarszy waitlister
    # sub-eventu) wskakuje, pozycje domknięte, reszta kolejności bez zmian
    e1.participations.find_by(user: u2).update!(status: :cancelled)

    assert_equal [ u1.id, u3.id, u4.id ], e1.participations.confirmed.order(:position).pluck(:user_id),
                 "promocja nie przetasowuje pozostałych"
    assert_equal [ 1, 2, 3 ], e1.participations.confirmed.order(:position).pluck(:position),
                 "pozycje zresequencowane bez dziur"
    assert_equal "confirmed", campaign.campaign_participations.find_by(user: u2).status,
                 "primary roster kampanii nietknięty"
  end

  # --- wypisanie się z JEDNEGO łapania --------------------------------------

  test "cancel na jednym sub-evencie nie rusza kampanii ani innych sub-eventów i promuje waitlistera tego sub-eventu" do
    campaign = build_campaign(capacity: 2)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 2)
    e2 = add_sub_event(campaign, name: "Łapanie 2", capacity: 2, scheduled_at: 3.days.from_now)

    u1, u2 = make_user("A"), make_user("B")
    cp1 = join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :confirmed, position: 2)

    # ktoś z feedu zapisał się tylko na to jedno łapanie, na rezerwę
    outsider = make_user("Outsider")
    Participation.create!(event: e1, user: outsider, status: :waitlist, position: 1)

    # u1 wypisuje się TYLKO z łapania 1 (ścieżka kontrolera = update na cancelled)
    e1.participations.find_by(user: u1).update!(status: :cancelled)

    assert_equal "confirmed", cp1.reload.status, "kampania nietknięta"
    assert_equal "confirmed", status_on(e2, u1), "drugie łapanie nietknięte"
    assert_equal "cancelled", status_on(e1, u1)
    assert_equal "confirmed", status_on(e1, outsider), "waitlister sub-eventu wskoczył na zwolnione miejsce"
    assert_equal [ 1, 2 ], e1.participations.confirmed.order(:position).pluck(:position), "pozycje zresequencowane"
  end

  test "po wypisaniu z jednego łapania można na nie wrócić (reaktywacja cancelled)" do
    campaign = build_campaign(capacity: 2)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 2)

    u1 = make_user("A")
    join_campaign(campaign, u1, status: :confirmed, position: 1)

    p = e1.participations.find_by(user: u1)
    p.update!(status: :cancelled)
    # powrót przez ścieżkę reaktywacji (jak ParticipationsController#create)
    p.reload.update!(status: :confirmed, position: 1)

    assert_equal "confirmed", status_on(e1, u1)
  end

  test "nowy sub-event dodany później dostaje aktualny primary roster — także usera, który wypisał się z innego łapania" do
    campaign = build_campaign(capacity: 2)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 2)

    u1, u2 = make_user("A"), make_user("B")
    join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :confirmed, position: 2)

    e1.participations.find_by(user: u1).update!(status: :cancelled)

    e3 = add_sub_event(campaign, name: "Łapanie 3", capacity: 2, scheduled_at: 5.days.from_now)

    assert_equal "confirmed", status_on(e3, u1), "wypisanie z jednego łapania nie wyklucza z nowych terminów"
    assert_equal "confirmed", status_on(e3, u2)
  end

  # --- anulacja całej kampanii (kaskada) -------------------------------------

  test "cancel primary confirmed -> promocja waitlistera kampanii + przejęcie miejsc na sub-eventach" do
    campaign = build_campaign(capacity: 1)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 1)
    e2 = add_sub_event(campaign, name: "Łapanie 2", capacity: 1, scheduled_at: 3.days.from_now)

    u1, u2 = make_user("A"), make_user("B")
    cp1 = join_campaign(campaign, u1, status: :confirmed, position: 1)
    cp2 = join_campaign(campaign, u2, status: :waitlist,  position: 1)

    cp1.update!(status: :cancelled)

    assert_equal "confirmed", cp2.reload.status, "waitlister kampanii promowany na primary"
    assert_equal "cancelled", status_on(e1, u1)
    assert_equal "cancelled", status_on(e2, u1)
    assert_equal "confirmed", status_on(e1, u2), "promowany przejmuje miejsce na sub-evencie 1"
    assert_equal "confirmed", status_on(e2, u2), "promowany przejmuje miejsce na sub-evencie 2"
    assert_equal 1, cp2.reload.position
  end

  test "kaskada anulacji nie dotyka sub-eventu, który już się rozpoczął" do
    campaign = build_campaign(capacity: 1)
    e_future = add_sub_event(campaign, name: "Przyszłe", capacity: 1)
    e_started = add_sub_event(campaign, name: "Trwa", capacity: 1, scheduled_at: 4.days.from_now)

    u1 = make_user("A")
    cp1 = join_campaign(campaign, u1, status: :confirmed, position: 1)
    assert_equal "confirmed", status_on(e_started, u1)

    # event startuje (update_column omija walidacje i callbacki — symulacja upływu czasu)
    e_started.update_column(:scheduled_at, 1.hour.ago)

    cp1.update!(status: :cancelled)

    assert_equal "cancelled", status_on(e_future, u1)
    assert_equal "confirmed", status_on(e_started, u1), "rozpoczęte łapanie zostaje bez zmian"
  end

  test "cancel z waitlisty kampanii tylko domyka pozycje — bez promocji i bez ruchu na sub-eventach innych userów" do
    campaign = build_campaign(capacity: 1)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 1)

    u1, u2, u3 = make_user("A"), make_user("B"), make_user("C")
    join_campaign(campaign, u1, status: :confirmed, position: 1)
    cp2 = join_campaign(campaign, u2, status: :waitlist, position: 1)
    cp3 = join_campaign(campaign, u3, status: :waitlist, position: 2)

    cp2.update!(status: :cancelled)

    assert_equal "waitlist", cp3.reload.status
    assert_equal 1, cp3.position, "luka po wypisanym waitlisterze domknięta"
    assert_equal "confirmed", status_on(e1, u1), "confirmed na sub-evencie nietknięty"
    assert_equal "cancelled", status_on(e1, u2), "waitlister znika też z sub-eventu"
  end

  test "ponowne dołączenie do kampanii po anulacji reaktywuje sub-eventy" do
    campaign = build_campaign(capacity: 2)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 2)

    u1 = make_user("A")
    cp1 = join_campaign(campaign, u1, status: :confirmed, position: 1)
    cp1.update!(status: :cancelled)
    assert_equal "cancelled", status_on(e1, u1)

    cp1.reload.update!(status: :confirmed, position: 1)

    assert_equal "confirmed", cp1.reload.status
    assert_equal "confirmed", status_on(e1, u1), "powrót do kampanii przywraca miejsce na sub-evencie"
  end

  test "podwójna anulacja tego samego uczestnictwa jest idempotentna" do
    campaign = build_campaign(capacity: 1)
    e1 = add_sub_event(campaign, name: "Łapanie 1", capacity: 1)

    u1 = make_user("A")
    cp1 = join_campaign(campaign, u1, status: :confirmed, position: 1)

    cp1.update!(status: :cancelled)
    assert_nothing_raised { cp1.reload.update!(status: :cancelled) }

    assert_equal "cancelled", status_on(e1, u1)
    assert_equal 0, campaign.campaign_participations.holding_slot.count
  end

  test "promocja na sub-evencie preferuje waitlistera będącego w stałym składzie kampanii" do
    campaign = build_campaign(capacity: 2)
    # sub-event o capacity 1 — drugi campaign-confirmed ląduje na jego waitliście
    e1 = add_sub_event(campaign, name: "Ciasne łapanie", capacity: 1)

    u1, u2 = make_user("A"), make_user("B")
    cp1 = join_campaign(campaign, u1, status: :confirmed, position: 1)
    join_campaign(campaign, u2, status: :confirmed, position: 2)
    assert_equal "waitlist", status_on(e1, u2)

    # outsider zapisał się na waitlistę sub-eventu WCZEŚNIEJ pozycyjnie? Nie —
    # u2 już jest position 1. Outsider wskakuje za nim; preferencja składu
    # kampanii i tak wybrałaby u2.
    outsider = make_user("Outsider")
    Participation.create!(event: e1, user: outsider, status: :waitlist, position: 2)

    cp1.update!(status: :cancelled)

    assert_equal "confirmed", status_on(e1, u2), "miejsce przejmuje członek stałego składu"
    assert_equal "waitlist",  status_on(e1, outsider)
  end
end
