class StatsService
  # Trofea „społeczności". Treść i kolejność żyją w `Stats::Trophies::ALL`
  # (osobny plik — to katalog, nie logika); tutaj są wyłącznie zapytania.
  # Kontroler woła `compute` i renderuje wynik 1:1.
  #
  # Dodanie nowego trofeum: wpis w katalogu + `compute_<key>` poniżej,
  # zwracająca posortowaną (najlepszy pierwszy) listę do 3 par
  # `[user_id, sformatowana_wartość]`. Pusta lista = brak zwycięzcy.
  TROPHIES = Stats::Trophies::ALL

  # Min liczba zapisów żeby user kwalifikował się do trofeów liczonych
  # procentowo (Niezawodny, Pechowiec) — broni przed jednorazowym lucky-shotem.
  MIN_PARTICIPATIONS_FOR_RATIO = 5

  # event_types są wartościami stringowymi (zwracane przez pluck(:event_type)
  # mimo że w DB siedzą jako integer — Rails enum zwraca string przy reads).
  # Trzymamy stałe jako stringi żeby nie żonglować typami.
  CONFIRMED_PRIOR_TYPES = %w[joined accepted promoted].freeze
  JOIN_TYPES = %w[joined joined_waitlist].freeze
  CANCELLED_TYPE = "cancelled".freeze
  WAITLIST_JOIN_TYPE = "joined_waitlist".freeze
  # Zdarzenia kończące pobyt na waitliście (Wytrwały Rezerwista).
  WAITLIST_EXIT_TYPES = %w[promoted cancelled swapped_in].freeze

  CACHE_KEY = "stats_service/compute".freeze
  # Dane trofeów zmieniają się wolno (nowe wpisy audit-logu przy zapisach /
  # wypisach), a pełny przelot to ~20 zapytań agregujących — 5 minut TTL
  # zdejmuje ten koszt z każdego renderu /statystyki.
  CACHE_TTL = 5.minutes

  # --- Orkiestracja ---------------------------------------------------------

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
    enabled_ids = User.enabled.where(id: user_ids_in(results)).pluck(:id).to_set
    results.transform_values! { |entries| entries.select { |uid, _| enabled_ids.include?(uid) } }

    # Cichy Bohater liczy się na końcu: kandydują tylko userzy, których nie ma
    # na ŻADNYM innym podium (ani zwycięzca, ani miejsca 2-3) — gwarancja, że
    # najaktywniejsi z pomijanych też mają swoją gablotę.
    results[:quiet_hero] = compute_quiet_hero(user_ids_in(results))
    results
  end

  # Dociąga rekordy User do surowych par — poza cachem, żeby wpisy userów
  # wyłączonych/usuniętych w trakcie TTL wypadały od razu (miejsce przejmuje
  # następny w rankingu).
  def self.hydrate(raw_results)
    users_by_id = User.enabled.with_attached_photo
                      .where(id: user_ids_in(raw_results))
                      .index_by(&:id)
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

  def self.user_ids_in(results)
    results.values.flatten(1).map(&:first).compact.uniq
  end

  # --- Trofea: zwykłe zliczenia --------------------------------------------

  def self.compute_waitlist
    top3_by_audit(WAITLIST_JOIN_TYPE)
  end

  def self.compute_flake
    top3_by_audit(CANCELLED_TYPE)
  end

  def self.compute_promoted
    top3_by_audit(:promoted)
  end

  def self.compute_ghoster
    top3_by_audit(:expired)
  end

  def self.compute_swapper
    top3_by_audit(:swapped_in)
  end

  def self.compute_negotiator
    top3_by_count(SwapProposal.all, :proposer_id)
  end

  def self.compute_passenger
    top3_by_count(CarpoolRequest.accepted)
  end

  def self.compute_hitchhiker
    top3_by_count(CarpoolRequest.all)
  end

  def self.compute_driver
    top3_by_count(CarpoolRequest.accepted.joins(:carpool_offer), "carpool_offers.user_id")
  end

  def self.compute_first_lady
    top3_by_count(Participation.where(status: :confirmed, position: 1))
  end

  def self.compute_last_man_in
    top3_by_count(
      Participation.joins(:event)
                   .where(status: :confirmed)
                   .where("participations.position = events.capacity")
    )
  end

  def self.compute_globetrotter
    top3_by_count(completed_confirmed, "participations.user_id", distinct: "events.host_id")
  end

  # Każde zlecenie liczy się raz — sub-eventy serii mają creator_id = NULL
  # (twórca siedzi na kampanii), więc spadamy na twórcę serii przez COALESCE.
  def self.compute_organizer
    attribution = "COALESCE(events.creator_id, event_campaigns.creator_id)"
    top3_by_count(
      Event.left_joins(:event_campaign).where(Arel.sql("#{attribution} IS NOT NULL")),
      attribution
    )
  end

  def self.compute_quiet_hero(featured_user_ids)
    scope = Participation.where(status: :confirmed)
    scope = scope.where.not(user_id: featured_user_ids) if featured_user_ids.any?
    top3_by_count(scope)
  end

  # --- Trofea: agregacje liczone w Ruby ------------------------------------

  def self.compute_hours
    rows = completed_confirmed.pluck("participations.user_id, events.scheduled_at, events.ends_at")

    sums = rows.each_with_object(Hash.new(0.0)) do |(uid, start_at, end_at), acc|
      acc[uid] += (end_at - start_at) / 3600.0
    end
    sums.sort_by { |_, hours| -hours }.first(3).map { |uid, hours| [ uid, hours.round ] }
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

  # Łączny czas przesiedziany na rezerwie — suma wszystkich pobytów na
  # waitliście. Pobyt kończy awans/wypis/wymiana, a gdy user dosiedział do
  # startu eventu (albo wciąż siedzi) — start eventu / teraz, cokolwiek
  # wcześniejsze. Celowo NIE bierzemy pojedynczego najdłuższego czekania:
  # przy evencie założonym z dużym wyprzedzeniem cała waitlista czeka
  # identycznie długo i podium robi się remisowe.
  def self.compute_patient
    pids = ParticipationEvent.where(event_type: WAITLIST_JOIN_TYPE).distinct.pluck(:participation_id)
    return [] if pids.empty?

    meta = participation_meta(pids)
    totals = Hash.new(0.0)

    history_by_participation(pids).each do |pid, events|
      info = meta[pid]
      next unless info

      waitlisted_at = nil
      events.each do |_, type, at|
        if type == WAITLIST_JOIN_TYPE
          waitlisted_at ||= at
        elsif waitlisted_at && WAITLIST_EXIT_TYPES.include?(type)
          totals[info[:uid]] += at - waitlisted_at
          waitlisted_at = nil
        end
      end

      next unless waitlisted_at # pobyt niezamknięty — trwa do startu eventu / teraz

      stint_end = [ Time.current, info[:scheduled_at] ].min
      totals[info[:uid]] += stint_end - waitlisted_at if stint_end > waitlisted_at
    end

    # Jedno miejsce po przecinku zamiast format_duration: łączne czasy potrafią
    # być bliskie (kilka osób czeka na tych samych eventach od utworzenia do
    # startu), a pełne dni sklejały podium w remis.
    totals.sort_by { |_, total| -total }
          .first(3)
          .map { |uid, total| [ uid, (total / 86_400).round(1).to_s.tr(".", ",") ] }
  end

  # --- Trofea: proporcje ----------------------------------------------------

  # Odwrotność Niesłownego: najniższy odsetek wycofań wśród userów z sensowną
  # liczbą zapisów (MIN_PARTICIPATIONS_FOR_RATIO — bez tego wygrywa każdy nowy).
  def self.compute_reliable
    joins   = audit_counts(JOIN_TYPES)
    cancels = audit_counts(CANCELLED_TYPE)

    joins.filter_map { |uid, join_count|
      next if join_count < MIN_PARTICIPATIONS_FOR_RATIO
      [ uid, (cancels.fetch(uid, 0) * 100.0 / join_count).round ]
    }.sort_by { |_, pct| pct }.first(3)
  end

  def self.compute_unlucky
    participation_status_counts.filter_map { |uid, c|
      total = c[:confirmed] + c[:waitlist]
      next if total < MIN_PARTICIPATIONS_FOR_RATIO
      [ uid, (c[:waitlist] * 100.0 / total).round ]
    }.sort_by { |_, pct| -pct }.first(3)
  end

  # --- Trofea: odstępy czasu ------------------------------------------------

  # Najmniejsza różnica między wycofaniem z głównej listy (confirmed→cancelled)
  # a startem eventu. Liczymy tylko gdy poprzednie audit-event dla tej samej
  # participation było joined/accepted/promoted (=user był na confirmed tuż
  # przed cancellem). Waitlist→cancelled NIE wchodzi — wycofanie z waitlisty
  # nikogo nie boli.
  def self.compute_last_minute
    shortest_gap_before_cancel(prev_types: CONFIRMED_PRIOR_TYPES) do |info, _prev_at, cancelled_at|
      info[:scheduled_at] - cancelled_at
    end
  end

  # Najkrótszy odstęp między joined/joined_waitlist a następującym po nim
  # cancelled — czyli świadomy zapis i odwrót. Reserved → cancelled (declined,
  # expired) NIE liczy się — to ścieżka mistrza, nie własna decyzja po zapisie.
  def self.compute_quick_undo
    shortest_gap_before_cancel(prev_types: JOIN_TYPES) do |_info, prev_at, cancelled_at|
      cancelled_at - prev_at
    end
  end

  # --- Trofea: pozostałe ----------------------------------------------------

  def self.compute_rookie
    User.joins(:participations).distinct
        .order(created_at: :desc)
        .limit(3)
        .pluck(:id, :created_at)
        .map { |uid, created_at| [ uid, created_at.strftime("%-d.%m.%Y") ] }
  end

  # --- Zapytania wielokrotnego użytku --------------------------------------

  # Kanoniczny kształt większości trofeów: policz wiersze per user, weź 3
  # najlepszych. `column` idzie i do GROUP BY, i do projekcji — jedno miejsce,
  # więc nie da się ich rozjechać. `distinct:` przełącza agregat na COUNT(DISTINCT).
  def self.top3_by_count(scope, column = :user_id, distinct: nil)
    aggregate = distinct ? "COUNT(DISTINCT #{distinct})" : "COUNT(*)"
    scope.group(Arel.sql(column.to_s))
         .order(Arel.sql("#{aggregate} DESC"))
         .limit(3)
         .pluck(Arel.sql("#{column}, #{aggregate}"))
  end

  def self.top3_by_audit(event_type)
    top3_by_count(audit_scope(event_type), "participations.user_id")
  end

  def self.audit_scope(event_type)
    ParticipationEvent.where(event_type: event_type).joins(:participation)
  end

  def self.audit_counts(event_type)
    audit_scope(event_type).group("participations.user_id").count
  end

  def self.completed_confirmed
    Participation.joins(:event)
                 .where(status: :confirmed)
                 .where.not(events: { completed_at: nil })
  end

  # Per-user counts confirmed vs waitlist. Memo pomijamy — service jest wołany
  # raz per przelot, query jest tani.
  def self.participation_status_counts
    rows = Participation.where(status: %i[confirmed waitlist]).group(:user_id, :status).count
    rows.each_with_object(Hash.new { |h, k| h[k] = { confirmed: 0, waitlist: 0 } }) do |((uid, status), count), acc|
      acc[uid][status.to_sym] = count
    end
  end

  # Pełna chronologiczna historia podanych participations — jedno query, bez
  # N+1. Zwraca { participation_id => [[pid, event_type, created_at], ...] }.
  def self.history_by_participation(pids)
    ParticipationEvent.where(participation_id: pids)
                      .order(:participation_id, :created_at, :id)
                      .pluck(:participation_id, :event_type, :created_at)
                      .group_by(&:first)
  end

  def self.participation_meta(pids)
    Participation.joins(:event).where(id: pids)
                 .pluck("participations.id, participations.user_id, events.scheduled_at")
                 .each_with_object({}) { |(pid, uid, at), h| h[pid] = { uid: uid, scheduled_at: at } }
  end

  # Wspólny szkielet Kurzego Tchórza i Klikam i Cofam: znajdź w historii każde
  # `cancelled` poprzedzone jednym z `prev_types`, zmierz odstęp blokiem
  # (info, prev_at, cancelled_at) i zwróć 3 najkrótsze — po jednym wyniku na
  # usera, sformatowane. Ujemne odstępy (cancel po starcie eventu) odpadają.
  def self.shortest_gap_before_cancel(prev_types:)
    pids = ParticipationEvent.where(event_type: CANCELLED_TYPE).distinct.pluck(:participation_id)
    return [] if pids.empty?

    meta = participation_meta(pids)
    candidates = []

    history_by_participation(pids).each do |pid, events|
      info = meta[pid]
      next unless info

      events.each_cons(2) do |(_, prev_type, prev_at), (_, type, at)|
        next unless type == CANCELLED_TYPE && prev_types.include?(prev_type)

        delta = yield(info, prev_at, at)
        candidates << [ info[:uid], delta ] if delta >= 0
      end
    end

    best_per_user(candidates) { |deltas| deltas.min }
      .sort_by { |_, delta| delta }
      .first(3)
      .map { |uid, delta| [ uid, format_duration(delta) ] }
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

    case seconds
    when ...60    then "#{seconds.round}s"
    when ...3600  then "#{(seconds / 60.0).round} min"
    when ...86_400 then "#{(seconds / 3600.0).round}h"
    else "#{(seconds / 86_400.0).round} dni"
    end
  end
end
