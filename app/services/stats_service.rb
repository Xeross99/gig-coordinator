class StatsService
  # Trofea „społeczności" — śmieszne kategorie dobrane tak, żeby zwycięzcy
  # naturalnie się rozjeżdżali (różne wektory: liczba, czas, pieniądze,
  # szybkość, role carpoolowe). Lista jest źródłem prawdy o kolejności +
  # treści — kontroler woła `compute` i renderuje wynik 1:1.
  #
  # Dodanie nowego trofeum: dopisz wpis do `TROPHIES` z `key:` + zaimplementuj
  # `compute_<key>` zwracającą posortowaną (najlepszy pierwszy) listę do 3 par
  # `[user_id, formatted_value]` — miejsce 1 renderuje się jako zwycięzca,
  # miejsca 2-3 jako mniejsze wiersze pod nim. Pusta lista = brak zwycięzcy.

  TROPHIES = [
    {
      key:         :hours,
      emoji:       "🏃",
      title:       "Maratończyk",
      description: "Najwięcej godzin spędzonych w kurniku. Wytrzymałość konia pociągowego.",
      unit:        "h"
    },
    {
      key:         :waitlist,
      emoji:       "🪑",
      title:       "Wieczna Rezerwa",
      description: "Najczęściej ląduje na liście rezerwowej.",
      unit:        "razy"
    },
    {
      key:         :flake,
      emoji:       "🥀",
      title:       "Niesłowny",
      description: "Najczęściej wycofuje zapis po potwierdzeniu. Dziś tak, jutro nie.",
      unit:        "wycofań"
    },
    {
      key:         :reliable,
      emoji:       "🎯",
      title:       "Niezawodny",
      description: "Najrzadziej wycofuje zapis. Jak się wpisał, to przyjdzie.",
      unit:        "% wycofań"
    },
    {
      key:         :last_minute,
      emoji:       "💨",
      title:       "Kurzy Tchórz",
      description: "Uciekł z głównej listy najbliżej startu zlecenia. Coś musiało wypaść.",
      unit:        "przed startem"
    },
    {
      key:         :organizer,
      emoji:       "📋",
      title:       "Organizator",
      description: "Stworzył najwięcej zleceń. Bez niego nikt by nie wiedział kiedy idziemy.",
      unit:        "zleceń"
    },
    {
      key:         :globetrotter,
      emoji:       "🧭",
      title:       "Obieżyświat",
      description: "Łapał u największej liczby gospodarzy. Wszędzie go znają.",
      unit:        "gospodarzy"
    },
    {
      key:         :passenger,
      emoji:       "🚗",
      title:       "Pasażer na Gapę",
      description: "Najczęściej dawał się podwieźć. Auto samo się nie pojawi.",
      unit:        "razy"
    },
    {
      key:         :promoted,
      emoji:       "⬆️",
      title:       "Awansowany",
      description: "Najczęściej skakał z rezerwy do głównej listy. Cierpliwość się opłaca.",
      unit:        "awansów"
    },
    {
      key:         :negotiator,
      emoji:       "🤝",
      title:       "Negocjator",
      description: "Najczęściej proponuje wymiany. Zawsze znajdzie sposób, żeby wskoczyć.",
      unit:        "propozycji"
    },
    {
      key:         :swapper,
      emoji:       "♻️",
      title:       "Rekin Wymian",
      description: "Najczęściej wchodził na główną listę przez wymianę. Handel kwitnie.",
      unit:        "wymian"
    },
    {
      key:         :patient,
      emoji:       "🛋️",
      title:       "Wytrwały Rezerwista",
      description: "Najwięcej czasu przesiedział łącznie na rezerwie. Cierpliwość z żelaza.",
      unit:        "dni na rezerwie"
    },
    {
      key:         :weekend,
      emoji:       "🍻",
      title:       "Weekendowy Wojownik",
      description: "Najwięcej zleceń w soboty i niedziele. Weekend to też praca.",
      unit:        "zleceń"
    },
    {
      key:         :quick_undo,
      emoji:       "🔄",
      title:       "Klikam i Cofam",
      description: "Najkrótszy odstęp między zapisem a wycofaniem. Zmienił zdanie zanim powiadomienie zdążyło wibrować.",
      unit:        nil
    },
    {
      key:         :hitchhiker,
      emoji:       "📞",
      title:       "Sygnalista",
      description: "Najwięcej zapytań o podwózkę wysłanych do kierowców. Przewieziony lub nie — pyta zawsze.",
      unit:        "zapytań"
    },
    {
      key:         :ghoster,
      emoji:       "👻",
      title:       "Mistrz Pauzy",
      description: "Najwięcej rezerwacji, które wygasły bez odpowiedzi. Mistrz Pióra w trybie offline.",
      unit:        "wygaśnięć"
    },
    {
      key:         :first_lady,
      emoji:       "🥇",
      title:       "Pierwsza Łapa",
      description: "Najczęściej pierwszy na potwierdzonej liście. Kto nie pierwszy, ten ostatni.",
      unit:        "razy"
    },
    {
      key:         :last_man_in,
      emoji:       "🚪",
      title:       "Ostatni Sprawiedliwy",
      description: "Najczęściej zajmował ostatnie miejsce na głównej liście. Drzwi zamknęli mu tuż za plecami.",
      unit:        "razy"
    },
    {
      key:         :rookie,
      emoji:       "🆕",
      title:       "Świeżynka",
      description: "Najświeższy nabytek wśród łapaczy. Witamy w klubie.",
      unit:        "rejestracja"
    },
    {
      key:         :unlucky,
      emoji:       "🎟️",
      title:       "Pechowiec",
      description: "Najwyższy procent zapisów lądujących na liście rezerwowej. Drugi rząd to jego dom.",
      unit:        "% rezerwy"
    },
    {
      key:         :driver,
      emoji:       "🚐",
      title:       "Człowiek-Bus",
      description: "Przewiózł najwięcej pasażerów. Wozi pół wsi.",
      unit:        "pasażerów"
    },
    {
      # Liczone na końcu, ze świadomością pozostałych wyników — patrz compute().
      key:         :quiet_hero,
      emoji:       "🤫",
      title:       "Cichy Bohater",
      description: "Żadnego pucharu na półce, a robota zrobiona. Ranking wyłącznie dla nieodznaczonych.",
      unit:        "zleceń"
    }
  ].freeze

  # Min liczba zapisów żeby user kwalifikował się do trofeów liczonych
  # procentowo (Snajper, Pechowiec) — broni przed jednorazowym lucky-shotem.
  MIN_PARTICIPATIONS_FOR_RATIO = 5

  # event_types są wartościami stringowymi (zwracane przez pluck(:event_type)
  # mimo że w DB siedzą jako integer — Rails enum zwraca string przy reads).
  # Trzymamy stałe jako stringi żeby nie żonglować typami.
  CONFIRMED_PRIOR_TYPES = %w[joined accepted promoted].freeze
  JOIN_TYPES = %w[joined joined_waitlist].freeze
  CANCELLED_TYPE = "cancelled".freeze
  # Zdarzenia kończące pobyt na waitliście (Wytrwały Rezerwista).
  WAITLIST_EXIT_TYPES = %w[promoted cancelled swapped_in].freeze

  CACHE_KEY = "stats_service/compute".freeze
  # Dane trofeów zmieniają się wolno (nowe wpisy audit-logu przy zapisach /
  # wypisach), a pełny przelot to ~20 zapytań agregujących — 5 minut TTL
  # zdejmuje ten koszt z każdego renderu /statystyki i strzału w API.
  CACHE_TTL = 5.minutes

  def self.compute
    # Cache trzyma wyłącznie czyste pary [user_id, wartość] (serializowalne,
    # zero obiektów AR) — rekordy User dociągamy poza cachem, więc wyłączenie
    # konta znika z podium natychmiast, nie dopiero po TTL.
    raw = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { compute_raw }
    hydrate(raw)
  end

  # Surowe wyniki wszystkich trofeów: { key => [[user_id, wartość], ...] }.
  def self.compute_raw
    regular = TROPHIES.reject { |t| t[:key] == :quiet_hero }
    results = regular.map { |t| [ t[:key], send("compute_#{t[:key]}") ] }.to_h

    # Wyłączone konta nie trzymają miejsc na podium — wycinamy je już tutaj,
    # żeby featured_ids (baza Cichego Bohatera) liczyły się jak dotychczas.
    user_ids = results.values.flatten(1).map(&:first).compact.uniq
    enabled_ids = User.enabled.where(id: user_ids).pluck(:id).to_set
    results.transform_values! { |entries| entries.select { |uid, _| enabled_ids.include?(uid) } }

    # Cichy Bohater liczy się na końcu: kandydują tylko userzy, których nie ma
    # na ŻADNYM innym podium (ani zwycięzca, ani miejsca 2-3) — gwarancja, że
    # najaktywniejsi z pomijanych też mają swoją gablotę.
    featured_ids = results.values.flatten(1).map(&:first).uniq
    results[:quiet_hero] = compute_quiet_hero(featured_ids)
    results
  end

  # Dociąga rekordy User do surowych par — poza cachem, żeby wpisy userów
  # wyłączonych/usuniętych w trakcie TTL wypadały od razu (miejsce przejmuje
  # następny w rankingu, jak dotąd w build_trophy).
  def self.hydrate(raw_results)
    user_ids = raw_results.values.flatten(1).map(&:first).compact.uniq
    users_by_id = User.enabled.with_attached_photo.where(id: user_ids).index_by(&:id)
    TROPHIES.map { |t| build_trophy(t, raw_results.fetch(t[:key], []), users_by_id) }
  end

  def self.build_trophy(trophy, raw_entries, users_by_id)
    entries = raw_entries.filter_map do |uid, value|
      user = users_by_id[uid]
      { user: user, value: value } if user
    end
    trophy.merge(
      winner:     entries.first&.dig(:user),
      value:      entries.first&.dig(:value),
      runners_up: entries.drop(1)
    )
  end

  def self.compute_hours
    rows = Participation.joins(:event)
                        .where(status: :confirmed)
                        .where.not(events: { completed_at: nil })
                        .pluck("participations.user_id, events.scheduled_at, events.ends_at")

    sums = rows.each_with_object(Hash.new(0.0)) do |(uid, start_at, end_at), acc|
      acc[uid] += (end_at - start_at) / 3600.0
    end
    sums.sort_by { |_, hours| -hours }.first(3).map { |uid, hours| [ uid, hours.round ] }
  end

  # Odwrotność Niesłownego: najniższy odsetek wycofań wśród userów z sensowną
  # liczbą zapisów (MIN_PARTICIPATIONS_FOR_RATIO — bez tego wygrywa każdy nowy).
  def self.compute_reliable
    joins = ParticipationEvent.where(event_type: JOIN_TYPES)
                              .joins(:participation)
                              .group("participations.user_id").count
    cancels = ParticipationEvent.where(event_type: CANCELLED_TYPE)
                                .joins(:participation)
                                .group("participations.user_id").count

    joins.filter_map { |uid, join_count|
      next if join_count < MIN_PARTICIPATIONS_FOR_RATIO
      [ uid, (cancels.fetch(uid, 0) * 100.0 / join_count).round ]
    }.sort_by { |_, pct| pct }.first(3)
  end

  def self.compute_globetrotter
    top3(
      Participation.joins(:event)
                   .where(status: :confirmed)
                   .where.not(events: { completed_at: nil })
                   .group(:user_id)
                   .order(Arel.sql("COUNT(DISTINCT events.host_id) DESC")),
      "participations.user_id, COUNT(DISTINCT events.host_id)"
    )
  end

  # Łączny czas przesiedziany na rezerwie — suma wszystkich pobytów na
  # waitliście. Pobyt kończy awans/wypis/wymiana, a gdy user dosiedział do
  # startu eventu (albo wciąż siedzi) — start eventu / teraz, cokolwiek
  # wcześniejsze. Celowo NIE bierzemy pojedynczego najdłuższego czekania:
  # przy evencie założonym z dużym wyprzedzeniem cała waitlista czeka
  # identycznie długo i podium robi się remisowe.
  def self.compute_patient
    pids = ParticipationEvent.where(event_type: :joined_waitlist).distinct.pluck(:participation_id)
    return [] if pids.empty?

    history = ParticipationEvent.where(participation_id: pids)
                                .order(:participation_id, :created_at, :id)
                                .pluck(:participation_id, :event_type, :created_at)
    meta = Participation.joins(:event).where(id: pids)
                        .pluck("participations.id, participations.user_id, events.scheduled_at")
                        .each_with_object({}) { |(pid, uid, at), h| h[pid] = { uid: uid, scheduled_at: at } }

    totals = Hash.new(0.0)
    history.group_by(&:first).each do |pid, events|
      info = meta[pid]
      next unless info

      waitlisted_at = nil
      events.each do |_, type, at|
        if type == "joined_waitlist"
          waitlisted_at ||= at
        elsif waitlisted_at && WAITLIST_EXIT_TYPES.include?(type)
          totals[info[:uid]] += at - waitlisted_at
          waitlisted_at = nil
        end
      end
      if waitlisted_at
        stint_end = [ Time.current, info[:scheduled_at] ].min
        totals[info[:uid]] += stint_end - waitlisted_at if stint_end > waitlisted_at
      end
    end

    # Jedno miejsce po przecinku zamiast format_duration: łączne czasy potrafią
    # być bliskie (kilka osób czeka na tych samych eventach od utworzenia do
    # startu), a pełne dni sklejały podium w remis.
    totals.sort_by { |_, total| -total }
          .first(3)
          .map { |uid, total| [ uid, (total / 86_400).round(1).to_s.tr(".", ",") ] }
  end

  def self.compute_negotiator
    top3(
      SwapProposal.group(:proposer_id).order(Arel.sql("COUNT(*) DESC")),
      "proposer_id, COUNT(*)"
    )
  end

  def self.compute_swapper
    top3(
      ParticipationEvent.where(event_type: :swapped_in)
                        .joins(:participation)
                        .group("participations.user_id")
                        .order(Arel.sql("COUNT(*) DESC")),
      "participations.user_id, COUNT(*)"
    )
  end

  def self.compute_quiet_hero(featured_user_ids)
    scope = Participation.where(status: :confirmed)
    scope = scope.where.not(user_id: featured_user_ids) if featured_user_ids.any?
    top3(
      scope.group(:user_id).order(Arel.sql("COUNT(*) DESC")),
      "user_id, COUNT(*)"
    )
  end

  # Dzień tygodnia liczymy w Ruby (`.in_time_zone`), nie w SQL — SQLite trzyma
  # timestampy w UTC, więc strftime('%w') mylił się o eventy tuż po północy
  # czasu polskiego (sobota 00:30 w Warszawie to piątek 22:30 UTC). Wolumen
  # danych jest mały (apka jednej fermy), agregacja w Ruby jest tania.
  def self.compute_weekend
    rows = Participation.joins(:event)
                        .where(status: :confirmed)
                        .pluck("participations.user_id, events.scheduled_at")

    counts = rows.each_with_object(Hash.new(0)) do |(uid, scheduled_at), acc|
      acc[uid] += 1 if scheduled_at.in_time_zone.on_weekend?
    end
    counts.sort_by { |_, count| -count }.first(3)
  end

  def self.compute_waitlist
    top3(
      ParticipationEvent.where(event_type: :joined_waitlist)
                        .joins(:participation)
                        .group("participations.user_id")
                        .order(Arel.sql("COUNT(*) DESC")),
      "participations.user_id, COUNT(*)"
    )
  end

  def self.compute_driver
    top3(
      CarpoolRequest.accepted
                    .joins(:carpool_offer)
                    .group("carpool_offers.user_id")
                    .order(Arel.sql("COUNT(*) DESC")),
      "carpool_offers.user_id, COUNT(*)"
    )
  end

  def self.compute_flake
    top3(
      ParticipationEvent.where(event_type: :cancelled)
                        .joins(:participation)
                        .group("participations.user_id")
                        .order(Arel.sql("COUNT(*) DESC")),
      "participations.user_id, COUNT(*)"
    )
  end

  # Najmniejsza różnica między wycofaniem z głównej listy (confirmed→cancelled)
  # a startem eventu. Liczymy tylko gdy poprzednie audit-event dla tej samej
  # participation było joined/accepted/promoted (=user był na confirmed tuż
  # przed cancellem). Waitlist→cancelled NIE wchodzi — wycofanie z waitlisty
  # nikogo nie boli.
  def self.compute_last_minute
    pids = ParticipationEvent.where(event_type: :cancelled).distinct.pluck(:participation_id)
    return [] if pids.empty?

    # Pełna chronologiczna historia wszystkich participations które kiedyś były
    # cancelled — w jednym query, posortowana, bez N+1.
    history = ParticipationEvent.where(participation_id: pids)
                                .order(:participation_id, :created_at, :id)
                                .pluck(:participation_id, :event_type, :created_at)
    by_pid = history.group_by(&:first)

    meta = Participation.joins(:event).where(id: pids)
                        .pluck("participations.id, participations.user_id, events.scheduled_at")
                        .each_with_object({}) { |row, h| h[row[0]] = { uid: row[1], scheduled_at: row[2] } }

    candidates = []
    by_pid.each do |pid, events|
      events.each_with_index do |(_, type, created_at), idx|
        next unless type == CANCELLED_TYPE
        next if idx.zero?
        prev_type = events[idx - 1][1]
        next unless CONFIRMED_PRIOR_TYPES.include?(prev_type)

        info = meta[pid]
        next unless info
        delta = info[:scheduled_at] - created_at
        next if delta < 0  # cancel po starcie eventu — nie liczymy
        candidates << [ info[:uid], delta ]
      end
    end

    best_per_user(candidates) { |deltas| deltas.min }
      .sort_by { |_, delta| delta }
      .first(3)
      .map { |uid, delta| [ uid, format_duration(delta) ] }
  end

  # Każde zlecenie liczy się raz — sub-eventy serii mają creator_id = NULL
  # (twórca siedzi na kampanii), więc spadamy na twórcę serii przez COALESCE.
  def self.compute_organizer
    attribution = "COALESCE(events.creator_id, event_campaigns.creator_id)"
    top3(
      Event.left_joins(:event_campaign)
           .where(Arel.sql("#{attribution} IS NOT NULL"))
           .group(Arel.sql(attribution))
           .order(Arel.sql("COUNT(*) DESC")),
      "#{attribution}, COUNT(*)"
    )
  end

  def self.compute_passenger
    top3(
      CarpoolRequest.accepted
                    .group(:user_id)
                    .order(Arel.sql("COUNT(*) DESC")),
      "user_id, COUNT(*)"
    )
  end

  def self.compute_promoted
    top3(
      ParticipationEvent.where(event_type: :promoted)
                        .joins(:participation)
                        .group("participations.user_id")
                        .order(Arel.sql("COUNT(*) DESC")),
      "participations.user_id, COUNT(*)"
    )
  end

  # Najkrótszy odstęp między joined/joined_waitlist a następującym po nim
  # cancelled — czyli świadomy zapis i odwrót. Reserved → cancelled (declined,
  # expired) NIE liczy się — to ścieżka mistrza, nie własna decyzja po zapisie.
  def self.compute_quick_undo
    pids_with_cancel = ParticipationEvent.where(event_type: :cancelled).distinct.pluck(:participation_id)
    return [] if pids_with_cancel.empty?

    history = ParticipationEvent.where(participation_id: pids_with_cancel)
                                .order(:participation_id, :created_at, :id)
                                .pluck(:participation_id, :event_type, :created_at)
    by_pid = history.group_by(&:first)
    pids_to_user = Participation.where(id: pids_with_cancel).pluck(:id, :user_id).to_h

    candidates = []
    by_pid.each do |pid, events|
      events.each_with_index do |(_, type, created_at), idx|
        next unless type == CANCELLED_TYPE
        next if idx.zero?
        prev_type, prev_at = events[idx - 1][1], events[idx - 1][2]
        next unless JOIN_TYPES.include?(prev_type)

        delta = created_at - prev_at
        next if delta < 0
        uid = pids_to_user[pid]
        next unless uid
        candidates << [ uid, delta ]
      end
    end

    best_per_user(candidates) { |deltas| deltas.min }
      .sort_by { |_, delta| delta }
      .first(3)
      .map { |uid, delta| [ uid, format_duration(delta) ] }
  end

  def self.compute_hitchhiker
    top3(
      CarpoolRequest.group(:user_id).order(Arel.sql("COUNT(*) DESC")),
      "user_id, COUNT(*)"
    )
  end

  def self.compute_ghoster
    top3(
      ParticipationEvent.where(event_type: :expired)
                        .joins(:participation)
                        .group("participations.user_id")
                        .order(Arel.sql("COUNT(*) DESC")),
      "participations.user_id, COUNT(*)"
    )
  end

  def self.compute_first_lady
    top3(
      Participation.where(status: :confirmed, position: 1)
                   .group(:user_id)
                   .order(Arel.sql("COUNT(*) DESC")),
      "user_id, COUNT(*)"
    )
  end

  def self.compute_last_man_in
    top3(
      Participation.joins(:event)
                   .where(status: :confirmed)
                   .where("participations.position = events.capacity")
                   .group(:user_id)
                   .order(Arel.sql("COUNT(*) DESC")),
      "user_id, COUNT(*)"
    )
  end

  def self.compute_rookie
    User.joins(:participations).distinct
        .order(created_at: :desc)
        .limit(3)
        .pluck(:id, :created_at)
        .map { |uid, created_at| [ uid, created_at.strftime("%-d.%m.%Y") ] }
  end

  def self.compute_unlucky
    counts = participation_status_counts
    candidates = counts.filter_map do |uid, c|
      total = c[:confirmed] + c[:waitlist]
      next if total < MIN_PARTICIPATIONS_FOR_RATIO
      [ uid, (c[:waitlist] * 100.0 / total).round ]
    end
    candidates.sort_by { |_, pct| -pct }.first(3)
  end


  # Helper: per-user counts confirmed vs waitlist participations. Memo
  # pomija — service jest wołany raz per request, query jest tani.
  def self.participation_status_counts
    rows = Participation.where(status: %i[confirmed waitlist]).group(:user_id, :status).count
    rows.each_with_object(Hash.new { |h, k| h[k] = { confirmed: 0, waitlist: 0 } }) do |((uid, status), count), acc|
      acc[uid][status.to_sym] = count
    end
  end

  def self.top3(scope, projection)
    scope.limit(3).pluck(Arel.sql(projection))
  end

  # Z listy kandydatów [uid, wartość] (user może mieć wiele) zostawia po
  # jednej — najlepszej — wartości per user, żeby podium nie zajęła trzykrotnie
  # ta sama osoba.
  def self.best_per_user(candidates)
    candidates.group_by(&:first)
              .map { |uid, rows| [ uid, yield(rows.map(&:last)) ] }
  end

  def self.format_duration(seconds)
    return "0s" if seconds <= 0

    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      minutes = seconds / 60.0
      "#{minutes.round} min"
    elsif seconds < 86_400
      hours = seconds / 3600.0
      "#{hours.round}h"
    else
      days = seconds / 86_400.0
      "#{days.round} dni"
    end
  end
end
