require "test_helper"

class StatsServiceTest < ActiveSupport::TestCase
  setup do
    @host = hosts(:jan)
    # Test env używa memory_store (nie null_store — rate limit testy trzymają
    # liczniki w Rails.cache), więc klucz statystyk trzeba czyścić ręcznie,
    # inaczej wynik z jednego testu przeciekłby do kolejnego.
    Rails.cache.delete(StatsService::CACHE_KEY)
  end

  teardown do
    Rails.cache.delete(StatsService::CACHE_KEY)
  end

  # Event bez auto-rezerwacji: fixtures userów są kurnikowymi gangsterami
  # (title 2), więc seed_reservations nie zaprasza nikogo (rezerwacje idą
  # wyłącznie do mistrzów pióra) — mirror build_event z reservation_service_test.rb.
  def build_event(scheduled_at:, capacity: 8, completed: false)
    Event.create!(
      host: @host, name: "Test",
      scheduled_at: scheduled_at, ends_at: scheduled_at + 2.hours,
      pay_per_person: 100, capacity: capacity,
      completed_at: completed ? scheduled_at + 3.hours : nil
    )
  end

  # Środa w południe — dzień powszedni z dala od północy, żeby eventy pomocnicze
  # nie wpadały ani w trofeum weekendowe, ani w pułapki stref czasowych.
  def next_wednesday_noon
    Time.zone.parse("#{Date.current.next_occurring(:wednesday)} 12:00")
  end

  def compute_fresh
    Rails.cache.delete(StatsService::CACHE_KEY)
    StatsService.compute
  end

  def trophy(trophies, key)
    trophies.find { |t| t[:key] == key }
  end

  # --- (a) wyłączone konta -------------------------------------------------

  test "wyłączony user wypada z podium a miejsce przejmuje następny aktywny" do
    base = next_wednesday_noon
    e1 = build_event(scheduled_at: base)
    e2 = build_event(scheduled_at: base + 1.hour)
    e3 = build_event(scheduled_at: base + 2.hours)
    # Ala: 2x pierwsza pozycja (wygrywa Pierwszą Łapę), Bartek: 1x.
    Participation.create!(event: e1, user: users(:ala), status: :confirmed, position: 1)
    Participation.create!(event: e2, user: users(:ala), status: :confirmed, position: 1)
    Participation.create!(event: e3, user: users(:bartek), status: :confirmed, position: 1)

    first_lady = trophy(compute_fresh, :first_lady)
    assert_equal users(:ala), first_lady[:winner]
    assert_equal users(:bartek), first_lady[:runners_up].first[:user]

    users(:ala).disable!

    first_lady = trophy(compute_fresh, :first_lady)
    assert_equal users(:bartek), first_lady[:winner],
                 "po wyłączeniu konta Ali podium przejmuje Bartek"
    all_users = [ first_lady[:winner], *first_lady[:runners_up].map { |e| e[:user] } ]
    assert_not_includes all_users, users(:ala),
                        "wyłączone konto nie może zostać nawet na miejscach 2-3"
  end

  test "wyłączony user znika z podium natychmiast, nawet gdy cache jest ciepły" do
    e1 = build_event(scheduled_at: next_wednesday_noon)
    Participation.create!(event: e1, user: users(:ala), status: :confirmed, position: 1)

    assert_equal users(:ala), trophy(StatsService.compute, :first_lady)[:winner]

    # Bez czyszczenia cache — hydratacja (lookup User.enabled) dzieje się poza
    # cachem, więc wyłączenie konta działa od razu, nie dopiero po TTL.
    users(:ala).disable!
    assert_nil trophy(StatsService.compute, :first_lady)[:winner]
  end

  # --- (b) próg MIN_PARTICIPATIONS_FOR_RATIO --------------------------------

  test "compute_reliable pomija userów poniżej progu MIN_PARTICIPATIONS_FOR_RATIO" do
    base = next_wednesday_noon
    # Create loguje 1x joined; resztę historii dopisujemy wprost do audit-logu.
    ala_part = Participation.create!(event: build_event(scheduled_at: base),
                                     user: users(:ala), status: :confirmed, position: 2)
    bartek_part = Participation.create!(event: build_event(scheduled_at: base + 1.hour),
                                        user: users(:bartek), status: :confirmed, position: 2)

    # Ala: 5 joinów (= próg) + 1 wycofanie → 20% i kwalifikacja.
    4.times { ala_part.participation_events.create!(event_type: :joined) }
    ala_part.participation_events.create!(event_type: :cancelled)
    # Bartek: 4 joiny, 0 wycofań — miałby 0% (wygrana), ale jest poniżej progu.
    3.times { bartek_part.participation_events.create!(event_type: :joined) }

    result = StatsService.compute_reliable
    assert_equal [ users(:ala).id ], result.map(&:first),
                 "Bartek (4 zapisy < #{StatsService::MIN_PARTICIPATIONS_FOR_RATIO}) nie kwalifikuje się mimo 0% wycofań"
    assert_equal 20, result.first.last # 1 wycofanie / 5 zapisów
  end

  # --- (c) Cichy Bohater ----------------------------------------------------

  test "quiet_hero kandyduja tylko userzy nieobecni na kazdym innym podium" do
    base = next_wednesday_noon
    # Ala: 3x pierwsza pozycja — okupuje podium Pierwszej Łapy. Mimo że ma
    # najwięcej potwierdzeń ze wszystkich, nie może być Cichym Bohaterem.
    3.times do |i|
      Participation.create!(event: build_event(scheduled_at: base + i.hours),
                            user: users(:ala), status: :confirmed, position: 1)
    end
    # Bartek i Cezary: po 1 potwierdzeniu — wylądują na podium Świeżynki
    # (3 najnowsi userzy z uczestnictwami), więc też odpadają z Cichego Bohatera.
    Participation.create!(event: build_event(scheduled_at: base + 3.hours),
                          user: users(:bartek), status: :confirmed, position: 2)
    Participation.create!(event: build_event(scheduled_at: base + 4.hours),
                          user: users(:cezary), status: :confirmed, position: 2)
    # Dominika: 2 potwierdzenia, ale rejestracja najstarsza — nie mieści się
    # w top-3 Świeżynki i nie wygrywa nic innego → jedyna kandydatka.
    users(:dominika).update!(created_at: 3.years.ago)
    Participation.create!(event: build_event(scheduled_at: base + 5.hours),
                          user: users(:dominika), status: :confirmed, position: 2)
    Participation.create!(event: build_event(scheduled_at: base + 6.hours),
                          user: users(:dominika), status: :confirmed, position: 3)

    trophies = compute_fresh
    assert_equal users(:ala), trophy(trophies, :first_lady)[:winner], "sanity: Ala jest odznaczona gdzie indziej"

    quiet = trophy(trophies, :quiet_hero)
    assert_equal users(:dominika), quiet[:winner],
                 "wygrywa Dominika (2 potwierdzenia), bo Ala (3) siedzi już na innym podium"
    assert_equal 2, quiet[:value]
    quiet_users = [ quiet[:winner], *quiet[:runners_up].map { |e| e[:user] } ]
    assert_not_includes quiet_users, users(:ala)
    assert_not_includes quiet_users, users(:bartek)
    assert_not_includes quiet_users, users(:cezary)
  end

  # --- (d) weekend liczony w strefie Warszawy --------------------------------

  test "weekend liczy sobote 00:30 czasu Warszawy (piatek w UTC) jako weekend" do
    saturday_night = Time.zone.parse("#{Date.current.next_occurring(:saturday)} 00:30")
    assert_predicate saturday_night.utc, :friday?, "sanity: w UTC to jeszcze piątek"
    Participation.create!(event: build_event(scheduled_at: saturday_night),
                          user: users(:ala), status: :confirmed, position: 1)

    # Kontrprzykład: poniedziałek 00:30 w Warszawie to niedziela w UTC — NIE
    # może liczyć się jako weekend (SQL-owe strftime na UTC by go doliczyło).
    monday_night = Time.zone.parse("#{Date.current.next_occurring(:monday)} 00:30")
    assert_predicate monday_night.utc, :sunday?, "sanity: w UTC to jeszcze niedziela"
    Participation.create!(event: build_event(scheduled_at: monday_night),
                          user: users(:bartek), status: :confirmed, position: 1)

    assert_equal [ [ users(:ala).id, 1 ] ], StatsService.compute_weekend
  end

  # --- cache -----------------------------------------------------------------

  test "compute cache'uje wylacznie surowe pary bez obiektow AR" do
    Participation.create!(event: build_event(scheduled_at: next_wednesday_noon),
                          user: users(:ala), status: :confirmed, position: 1)
    StatsService.compute

    cached = Rails.cache.read(StatsService::CACHE_KEY)
    assert_kind_of Hash, cached
    assert cached.key?(:quiet_hero)
    cached.each do |key, entries|
      entries.each do |uid, value|
        assert_kind_of Integer, uid, "#{key}: user_id musi być czystym integerem"
        assert_not_kind_of ActiveRecord::Base, value, "#{key}: żadnych rekordów AR w cache"
      end
    end
  end

  test "compute korzysta z cache w oknie TTL" do
    e1 = build_event(scheduled_at: next_wednesday_noon)
    Participation.create!(event: e1, user: users(:ala), status: :confirmed, position: 1)
    assert_equal users(:ala), trophy(StatsService.compute, :first_lady)[:winner]

    # Bartek wyprzedza Alę, ale cache jeszcze żyje → stary zwycięzca.
    2.times do |i|
      Participation.create!(event: build_event(scheduled_at: next_wednesday_noon + (i + 1).hours),
                            user: users(:bartek), status: :confirmed, position: 1)
    end
    assert_equal users(:ala), trophy(StatsService.compute, :first_lady)[:winner]

    # Po wygaśnięciu klucza wynik jest przeliczony od zera.
    assert_equal users(:bartek), trophy(compute_fresh, :first_lady)[:winner]
  end
end
