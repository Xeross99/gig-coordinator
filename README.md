# Gig Coordinator

Rails 8.1 aplikacja do koordynacji pracy dorywczej w rolnictwie. **Organizatorzy (Hosts)** tworzą eventy typu „Wydarzenie"; **Pracownicy (Users)** akceptują je z mobilnej PWA. Polski UI, PL ścieżki URL, logowanie wyłącznie przez magic-link, real-time przez Turbo Streams, web push przez VAPID.

## Stack

- **Rails 8.1**, **Ruby 4.0**
- **SQLite** + Active Storage (zdjęcia hostów i userów)
- **Hotwire** — Turbo + Stimulus
- **Tailwind v4** (watcher w Procfile.dev, custom keyframes w `@theme`)
- **`@tailwindplus/elements`** (dropdown web-components, pinned w importmap)
- **Solid Queue / Solid Cache / Solid Cable** (in-DB, bez Redis)
- **web-push** (VAPID)
- **rails-i18n** (polska lokalizacja + transliteracja slugów)

## Uruchomienie

```bash
bin/setup                            # bundle + db:prepare
bin/dev                              # Puma + tailwindcss:watch (honoruje $PORT)
PORT=3001 bin/dev                    # inny port (gdy :3000 zajęty)
bin/rails db:seed                    # sample hostów, userów i eventów
bin/rails test                       # unit + integration
bin/rails test:system                # Capybara + headless Chrome
bin/login-link <email>               # wypisz URL magic-linka (honoruje PUBLIC_HOST + PORT)
bin/ci                               # pełny CI run: setup, rubocop, gem audit, brakeman, testy, seedy
```

Credentiale (patrz `CLAUDE.md`): Gmail SMTP + VAPID keys + deliverable `subject` mailto.

---

# Modele i relacje

Aplikacja ma **7 modeli**. Dwa z nich (`Host` i `User`) są niezależnymi modelami uwierzytelnialnymi — **nie STI, nie jeden model z kolumną `role`**. Każdy ma własny cykl życia, własny panel i własne relacje.

```
Host ──< Event ──< Participation >── User
                                    │
                                    └──< PushSubscription
Session (polimorficzna) ── Host | User
```

## `Host` — organizator

Właściciel eventów. Zarządza nimi z panelu `/host/*`.

**Tabela `hosts`:**
| Kolumna     | Typ                      | Uwagi                         |
|-------------|--------------------------|-------------------------------|
| id          | integer PK               |                               |
| first_name  | string, NOT NULL         |                               |
| last_name   | string, NOT NULL         |                               |
| email       | string, NOT NULL, UNIQUE | case-insensitive (normalized) |
| location    | string, NOT NULL         | miejscowość/adres tekstowy    |
| timestamps  |                          |                               |

> Wcześniejsza migracja `CreateHosts` dodawała spekulacyjnie kolumny `lat` / `lng` (decimal, precision: 10, scale: 6) pod przyszłą geolokalizację — były nieużywane, więc zostały zdjęte w migracji `RemoveLatLngFromHosts`.

**Relacje:**
- `has_many :events, dependent: :destroy` — eventy, które stworzył
- `has_many :sessions, as: :authenticatable, dependent: :destroy` — aktywne sesje (polimorficzne)
- `has_one_attached :photo` — zdjęcie profilowe (Active Storage)

**Walidacje:** `first_name`, `last_name`, `location`, `email` (format + unikalność).

**Metody instancji:** `display_name` → `"#{first_name} #{last_name}"`.

**Normalizacje:** `email` → strip + downcase (`normalizes :email`).

**Uwierzytelnianie:** magic-link (`signed_id(purpose: :magic_link, expires_in: 15.minutes)`). Host loguje się na tym samym `/login` co User — `MagicLinksController` sprawdza najpierw `Host`, potem `User`.

---

## `User` — pracownik

Konsument eventów. Przegląda feed, akceptuje / anuluje, instaluje PWA, dostaje push.

**Tabela `users`:**
| Kolumna     | Typ                      | Uwagi                                                     |
|-------------|--------------------------|-----------------------------------------------------------|
| id          | integer PK               |                                                           |
| first_name  | string, NOT NULL         |                                                           |
| last_name   | string, NOT NULL         |                                                           |
| email       | string, NOT NULL, UNIQUE | case-insensitive (normalized)                             |
| title       | integer, DEFAULT 0, idx  | enum ranga: `rookie` (0) → `master` (3)         |
| timestamps  |                          |                                                           |

**Relacje:**
- `has_many :participations, dependent: :destroy` — uczestnictwa (confirmed/waitlist/cancelled)
- `has_many :events, through: :participations` — eventy, w których bierze udział
- `has_many :push_subscriptions, dependent: :destroy` — subskrypcje web push (1 user może mieć wiele urządzeń)
- `has_many :sessions, as: :authenticatable, dependent: :destroy` — aktywne sesje
- `has_one_attached :photo` — zdjęcie profilowe (Active Storage) z nazwanym variantem `:roster` (`resize_to_fill: [40, 40]`) używanym we wszystkich listach roster na `/eventy/:id`

**Walidacje:** `first_name`, `last_name`, `email` (format + unikalność).

**Enum `:title`:** 4 rangi (`rookie`, `member`, `veteran`, `master`). Default w bazie = 0 (`rookie`) — każdy nowy user zaczyna jako Nowy, promocja ręcznie przez konsolę. Labelki w `config/locales/pl.yml` pod `user.titles.*`; `user.display_title` zwraca przetłumaczony tekst.

**Badge rangi (UI):** `User::TITLE_BADGE_COLORS` + `#title_badge_classes` mapują rangę na parę `bg-*` / `text-*`: **szary** = Nowy (najniższa) → **zielony** = Członek → **fioletowy** = Weteran → **żółty/złoty** = Mistrz (najwyższa). Partial `app/views/users/_title_badge.html.erb` (locals: `user:`) renderuje kapsułkę `inline-flex ... rounded-md ... text-xs`. Używany wszędzie, gdzie pokazujemy użytkownika z rangą: `/pracownicy`, navbar usera, `/profil/edit`, każdy wiersz roster na `/eventy/:id`.

**Metody instancji:** `display_name`, `display_title`, `title_badge_classes`.

**Normalizacje:** `email` → strip + downcase.

**Profil:** `/profil/edit` (`ProfilesController`) pozwala zmienić **tylko zdjęcie**. Imię, nazwisko, email i ranga są read-only w UI (edycja przez `rails console`) — decyzja projektowa: email jest kluczem magic-linka, zmiana z poziomu UI otwierałaby wektor ataku.

---

## `Event` — wydarzenie

Konkretna „robota" z datą startu/końca, stawką i liczbą miejsc.

**Tabela `events`:**
| Kolumna         | Typ                | Uwagi                                    |
|-----------------|--------------------|------------------------------------------|
| id              | integer PK         |                                          |
| host_id         | integer FK, NOT NULL | `belongs_to :host`                     |
| name            | string, NOT NULL   | np. „Wydarzenie — Wilga"               |
| scheduled_at    | datetime, NOT NULL | początek (index)                         |
| ends_at         | datetime, NOT NULL | koniec (index)                           |
| pay_per_person  | decimal(8,2), NOT NULL, ≥ 0 | stawka brutto za osobę          |
| capacity        | integer, NOT NULL, > 0 | liczba miejsc confirmed              |
| completed_at    | datetime           | NULL dopóki nie rozliczony               |
| timestamps      |                    |                                          |

**Relacje:**
- `belongs_to :host`
- `has_many :participations, dependent: :destroy`
- `has_many :users, through: :participations`

**Walidacje:** `name`, `scheduled_at`, `ends_at`, `pay_per_person` (≥ 0), `capacity` (integer > 0). Custom: `ends_at_after_scheduled_at` — `ends_at` musi być po `scheduled_at`.

**Scope'y:**
- `upcoming` — `scheduled_at > Time.current`, sorted asc
- `awaiting_completion` — `ends_at < now AND completed_at IS NULL` (do job'a kończącego event)

**Metody:**
- `to_param` → `"#{id}-#{name.parameterize}"` (np. `/eventy/42-lapanie-kur`). Polskie znaki są transliterowane przez `rails-i18n` (Ł→l, ą→a…). `Event.find` dalej działa — Rails coerce'uje `"42-foo".to_i → 42`.
- `completed?` — czy ma `completed_at`
- `confirmed_count`, `waitlist_count` — liczniki
- `full?` — `confirmed_count >= capacity`

**Callbacki (broadcasty feedu — synchroniczne):**
- `after_create_commit :broadcast_feed_append` — prepend kartki do `events_list` w streamie `:events` (tylko jeśli `upcoming_now?`)
- `after_create_commit :notify_new_event_subscribers` — `WebPushNotifier.perform_later(:new_event, ...)` do wszystkich userów z push sub
- `after_update_commit :broadcast_feed_replace` — replace kartki
- `after_destroy_commit :broadcast_feed_remove` — remove z feedu

**Broadcasty są `broadcast_prepend_to` (sync), nie `_later`** — UI nie zależy od kolejki.

---

## `Participation` — relacja User ↔ Event

Wynik kliknięcia „Akceptuję" lub „Dołącz na listę rezerwową". Przechowuje stan + pozycję w kolejce.

**Tabela `participations`:**
| Kolumna         | Typ                 | Uwagi                                                        |
|-----------------|---------------------|--------------------------------------------------------------|
| id              | integer PK          |                                                              |
| event_id        | integer FK, NOT NULL |                                                             |
| user_id         | integer FK, NOT NULL |                                                             |
| status          | integer, NOT NULL, default 0 | enum: `confirmed=0, waitlist=1, cancelled=2, reserved=3` |
| position        | integer, NOT NULL, default 0 | pozycja w obrębie statusu                           |
| reserved_until  | datetime, nullable  | deadline rezerwacji (tylko dla `reserved`); nil poza tym     |
| timestamps      |                     |                                                              |

**Indexy:**
- `unique(event_id, user_id)` — jeden user = jeden rekord per event (jakikolwiek status)
- `(event_id, status, position)` — szybki lookup najstarszego na waitlist przy promocji
- `reserved_until` — do szybkiego sweepa wygasłych rezerwacji

**Relacje:**
- `belongs_to :event`
- `belongs_to :user`

**Walidacje:** `user_id` unique scope `event_id`.

**Scope'y:**
- `active` — wszystko poza `cancelled`
- `holding_slot` — confirmed + reserved (blokują capacity)

**Metody:** `reservation_expired?` — `reserved? && reserved_until <= now`.

**Logika biznesowa — NIE W MODELU:** create/destroy wywołuje `ParticipationsController` pod **pessimistic lockiem** na Event:

```ruby
Event.transaction do
  event.lock!
  confirmed_count = event.participations.confirmed.count
  if confirmed_count < event.capacity
    # confirmed, pozycja = confirmed_count
  else
    # waitlist, pozycja = waitlist_count
  end
end
```

Anulowanie `confirmed` odpala `promote_from_waitlist` — najstarszy `waitlist` (po `position`) staje się `confirmed`. Promocja wysyła `PromotionMailer` + `WebPushNotifier(:promotion)`. Wszystko w tej samej transakcji.

**Priority reservations (ranked auto-invites):** przy tworzeniu nowego eventu `Event#after_create_commit :seed_reservations` woła `ReservationService.seed_on_create(event)` → rezerwuje sloty wyłącznie dla **globalnie najwyższej rangi w systemie** (`User.maximum(:title)`). Nigdy nie schodzi niżej — ani przy seedzie, ani przy refillu. Np. capacity 4 + tylko 1 user `master` → 1 rezerwacja, pozostałe 3 sloty zostają otwarte na regularny flow. Ordering w obrębie tej samej rangi: `id ASC`. Każdy zaproszony dostaje `InvitationMailer#notify` + `WebPushNotifier(:invitation, ...)` + `reserved_until = now + 1h`.

Na `/eventy/:id` widzi dedykowany banner + przyciski **Akceptuję** / **Odrzuć** — obsługiwane przez `ParticipationsController#accept` i `#decline` (przyciski mają `data-turbo-frame="_top"` żeby submisja wyszła z ramki i toast pokazał się bez F5). Akceptacja flipuje `reserved → confirmed`. Odrzucenie → `cancelled` + `ReservationService.refill_one(event)` z semantyką **waitlist-first, potem tylko top-tier**:

1. Jeśli na waitliście ktoś czeka — promujemy go (spełnia regułę „jesli nie to wskakuje osoba w kolejce").
2. Jeśli waitlista pusta — szukamy innego usera z globalną najwyższą rangą, który nie ma jeszcze participation na tym evencie. Jeśli nie istnieje, slot zostaje pusty. **Żaden user niższej rangi nigdy nie dostanie auto-rezerwacji**, nawet jeśli wszyscy z top tieru już odrzucili.

`ReservationExpirationJob` (cron co minutę w dev i prod, `config/recurring.yml`) przegląda `Participation.reserved.where("reserved_until <= ?", Time.current)` i funneluje przez tę samą logikę co decline. Klasy: `app/services/reservation_service.rb`, `app/jobs/reservation_expiration_job.rb`, `app/mailers/invitation_mailer.rb`.

**Model-level broadcasts:** `Participation#after_commit :broadcast_event_updates, on: %i[create update destroy]` wysyła `broadcast_replace_to [event, :roster]` + `[event, :counts]` przy każdej zmianie. Każda ścieżka (kontroler, service, job, `rails runner`, `rails console`) automatycznie odświeża otwarte przeglądarki — nie trzeba broadcastować ręcznie. Guard `Event.find_by(id: event_id)` chroni przed błędem przy kaskadowym destroy.

---

## `Session` — polimorficzna sesja

Jedna tabela dla Hostów i Userów.

**Tabela `sessions`:**
| Kolumna              | Typ                  | Uwagi                              |
|----------------------|----------------------|------------------------------------|
| id                   | integer PK           |                                    |
| token                | string, NOT NULL, UNIQUE | `SecureRandom.urlsafe_base64(32)` |
| authenticatable_type | string, NOT NULL     | `"Host"` albo `"User"`             |
| authenticatable_id   | integer, NOT NULL    |                                    |
| user_agent           | string               | dla debugowania                    |
| ip_address           | string               | dla debugowania                    |
| timestamps           |                      |                                    |

**Relacje:** `belongs_to :authenticatable, polymorphic: true`.

**Callbacki:** `before_validation :ensure_token` — generuje `token` jeśli brak.

**Jak działa:** `ApplicationController#load_current_session` czyta signed, permanent cookie `:session_token`, znajduje sesję, ustawia `Current.session`. Helpers `Current.host` / `Current.user` zwracają konkretny typ albo `nil`.

---

## `PushSubscription` — urządzenie subskrybujące web push

Każde urządzenie mobilne (instalacja PWA na Home Screen na iOS / Android) rejestruje swój endpoint.

**Tabela `push_subscriptions`:**
| Kolumna     | Typ                  | Uwagi                                       |
|-------------|----------------------|---------------------------------------------|
| id          | integer PK           |                                             |
| user_id     | integer FK, NOT NULL |                                             |
| endpoint    | string, NOT NULL, UNIQUE | URL dostarczany przez push service      |
| p256dh_key  | string, NOT NULL     | klucz public ECDH z Push API                |
| auth_key    | string, NOT NULL     | klucz auth z Push API                       |
| timestamps  |                      |                                             |

**Relacje:** `belongs_to :user`.

**Walidacje:** wszystkie 3 pola obecne, `endpoint` unikalny globalnie.

**Kto wysyła:** `WebPushNotifier` (ActiveJob, Solid Queue). Dispatch po `kind`:
- `:completion` / `:promotion` — do konkretnego usera (przez `participation_id:`)
- `:new_event` — do **wszystkich** userów z subskrypcją (feed jest publiczny)

Przy błędzie `InvalidSubscription` / `Expired` subskrypcja jest usuwana. Wszystkie inne `WebPush::ResponseError` są rescuowane i logowane — jeden zły endpoint nie wywala całej paczki.

**VAPID gotcha:** Apple Push zwraca `BadJwtToken` gdy `sub` w kluczach VAPID jest nieroutowalnym mailto (np. `mailto:admin@gig-coordinator.local`). Musi być prawdziwy adres.

---

## `Current` — Thread-local

`ActiveSupport::CurrentAttributes` z jednym atrybutem `session`, plus helpery `host` / `user` rzutujące `session.authenticatable` na konkretny typ (albo `nil`).

---

# Kluczowe flow'y

## Logowanie (magic-link)

1. `/logowanie` — jeden formularz dla Hosta i Usera (własny `auth` layout, pełen viewport bez navbaru).
2. `MagicLinksController#create` — szuka emaila najpierw w `Host`, potem w `User`. Zawsze `redirect_to login_path, notice: t("auth.check_email")` (no enumeration). Flash pokazuje się jako dismissable toast (`shared/_toast.html.erb`). W **dev** dodatkowo robi `puts` URL-a do stdout — widać go w logu `bin/dev`, nie trzeba otwierać maila.
3. Mail zawiera link z `signed_id(purpose: :magic_link, expires_in: 15.minutes)`.
4. `#show` — weryfikuje token dla obu modeli, tworzy `Session`, podpisuje cookie, redirect:
   - Host → `/panel`
   - User → `/`

**Dwa komunikaty — nie mylić ich:**
- `auth.invalid_token` („Ten link wygasł lub jest nieprawidłowy.") — tylko gdy `MagicLinksController#show` odrzuca token (bogus/expired).
- `auth.login_required` („Zaloguj się, aby kontynuować.") — gdy `require_user!` / `require_host!` z `ApplicationController` przekierowuje niezalogowanego.

Wcześniej obie ścieżki używały `invalid_token`, co wprowadzało w błąd userów, którzy po prostu nie byli zalogowani.

**Brak rejestracji.** Host/User powstają tylko przez `rails console` lub `db/seeds.rb`. Dodanie signup controllera zmieniłoby security model (email staje się niezautentykowanym write vector).

## Mailery

Wszystkie transakcyjne maile dzielą ten sam wygląd: rounded biała karta z szarym nagłówkiem (ikonka kury + „Gig Coordinator"), centralny content i stopka. Chrome siedzi w `app/views/layouts/mailer.html.erb` (+ `.text.erb`) — każdy mailer dziedziczy przez `ApplicationMailer.layout "mailer"`.

Cztery partials w `app/views/mailers/` do budowy treści: `_title`, `_paragraph` (przyjmuje `html:` → w razie potrzeby `safe_join([tag.strong(...), ...])`), `_cta_button` (label + url), `_raw_url` (fallback „jeśli przycisk nie działa"). Dodanie nowego maila sprowadza się do renderowania tych klocków.

Aktualne mailery: `MagicLinkMailer` (login), `PromotionMailer` (awans z waitlisty), `InvitationMailer` (rezerwacja z 1h deadline). Nie ma `CompletedEventMailer` — po zakończeniu eventu wystarczy push (`WebPushNotifier(:completion)`).

Mailer previews: `test/mailers/previews/`. Lista przykładów pod `/rails/mailers`. Dodanie nowego preview wymaga restartu `bin/dev`.

## Akceptacja eventu

User klika „Akceptuję" → `ParticipationsController#create`:
1. `Event.transaction do; event.lock!` (pessimistic row lock — serializuje równoległych klikaczy)
2. Szuka istniejącego `participation` dla `(event, user)`:
   - `nil` → insert nowy
   - `cancelled` → reaktywacja (`update!(status:, position:)`)
   - `confirmed`/`waitlist` → no-op (idempotent — ochrona przed spam-clickiem)
3. `next_slot_for` — jeśli `confirmed.count < capacity` → nowy rekord `confirmed`, inaczej `waitlist`. Pozycja z `max(position) + 1`.
4. Broadcast Turbo Stream do `[event, :counts]` i `[event, :roster]` (user + host oglądają ten sam partial rosteru).

Anulowanie:
1. Lock jak wyżej.
2. Jeśli cancelujemy `confirmed` → `promote_from_waitlist`: najstarszy waitlist → confirmed. Mail + push do promowanego.
3. Broadcast obu streamów.

**UI bez skoku scrolla:** przycisk akceptacji jest owinięty w `turbo_frame_tag`. `button_to` submituje, kontroler robi redirect, Turbo wyciąga pasującą ramkę z odpowiedzi i podmienia ją w miejscu — żadnej pełnej nawigacji.

## Zakończenie eventu

`EventCompletionJob` (recurring) skanuje `Event.awaiting_completion`, oznacza `completed_at` i wysyła `WebPushNotifier(:completion)` do confirmed userów. (Maila podziękowania nie ma — push wystarczy.)

---

# Turbo Streams

| Stream name        | Kto subskrybuje                   | Co się dzieje                                           |
|--------------------|-----------------------------------|---------------------------------------------------------|
| `[event, :counts]` | user event show                   | Participation `after_commit` (model callback)           |
| `[event, :roster]` | user + host event show            | Participation `after_commit` (model callback)           |
| `:events`          | user feed (`/`)                   | Event create/update/destroy + broadcast `visit`         |
| `[user, :events]`  | user feed (`/`)                   | user-scoped card replace przy rezerwacji (`invite!`)    |

**Broadcasty z modelu:** `Participation#after_commit` odpala `broadcast_replace_to` na `[event, :roster]` + `[event, :counts]` przy każdym create/update/destroy — single source of truth. Każda ścieżka (kontroler, service, job, runner) odświeża UI automatycznie. Feed broadcasty z `Event` model callbacks — synchronicznie. Roster partial (`app/views/events/_roster.html.erb`) współdzielony między hostem a userem; avatar przez `_roster_avatar.html.erb` (zdjęcie lub inicjały). Brak numerków pozycji — licznik jest w nagłówku sekcji.

**Adapter cable:** `solid_cable` w dev i prod (wcześniej dev miał `async`, który nie działa między procesami — broadcast z `bin/rails runner` nie docierał do przeglądarki). W dev jest osobna baza `storage/development_cable.sqlite3` pod cable (multi-DB w `config/database.yml`, migracje w `db/cable_migrate`). Po klonie repo: `bin/rails db:prepare` tworzy obie bazy.

**Active Storage w broadcastach:** `_roster_avatar.html.erb` używa `rails_representation_path(user.photo.variant(:roster), only_path: true)` — helper **path**, nie URL. Partial leci przez cable z dowolnego wątku (controller, service, job, runner), a tam `ActiveStorage::Current.url_options` jest nilem → przekazanie varianta wprost do `image_tag` wywalało się z "Cannot generate URL … please set ActiveStorage::Current.url_options" i podstawiało pusty `src`. Path helper nie próbuje budować absolutnego URL-a — przeglądarka dokleja host z bieżącej strony i trafia do `ActiveStorage::Representations::RedirectController`, gdzie `before_action` ustawia `Current.url_options` normalnie. Variant `:roster` (40×40 `resize_to_fill`) zdefiniowany bezpośrednio w modelu `User` przez `has_one_attached :photo do |attachable| attachable.variant :roster, ... end`.

**Custom Turbo Stream action `visit`:** zdefiniowane w `app/javascript/application.js` jako `Turbo.StreamActions.visit` — odpala `Turbo.visit(url)` po odebraniu `<turbo-stream action="visit" target="/path">`. Używane przez `Event#broadcast_visit_to_feed` żeby przenieść wszystkich userów na feedzie na stronę nowo utworzonego eventu.

---

# Routes — polskie ścieżki, angielskie helpery

URL-e są polskie, helpery Rails zostają po angielsku (żeby widoki/testy nie musiały się zmieniać):

```ruby
get    "logowanie",             to: "sessions#new",       as: :login
namespace :host, path: "panel", module: "host_admin" do
  resources :events,  path: "eventy"
  resource  :profile, path: "profil"
end
resources :events, only: %i[index show], path: "eventy" do
  resource :participation, path: "uczestnictwo"
end
resource  :profile, only: %i[edit update], path: "profil"
```

Mapowania: `/login` → `/logowanie`, `/session` → `/sesja`, `/host` → `/panel`, `/events` → `/eventy`, `/profile` → `/profil`, `/push_subscriptions` → `/subskrypcje-push`, `/events/:id/participation` → `/eventy/:id/uczestnictwo`, `/hosts` → `/organizatorzy`, `/users` → `/pracownicy`.

# Namespace Host panel

Routes mapują `/panel/*` na kontrolery `HostAdmin::` — bo `Host` to już klasa AR, więc `Host::EventsController` zderzyłoby się z Zeitwerkiem. Wpięte przez:

```ruby
namespace :host, path: "panel", module: "host_admin" do
  # ...
end
```

Dodając nowe kontrolery host-scoped, zachowaj ten wzorzec (`path:` PL, `as:`/module EN).

---

# Layouty i partials

- **`layouts/application.html.erb`** — aplikacja usera. Sticky navbar z avatarem (zdjęcie lub inicjały) + imię + **kolorowy badge rangi** (partial `users/_title_badge`), plus **dropdown menu** (`<el-dropdown>` + `<el-menu popover>` z `@tailwindplus/elements`) z trzema oddzielonymi sekcjami: (1) Mój profil, (2) Wszyscy pracownicy + Wszyscy organizatorzy, (3) Wyloguj. `<main class="max-w-lg mx-auto">` (poszerzone z `max-w-md` pod większe telefony).
- **`layouts/host_admin.html.erb`** — panel hosta. Prosty header, `max-w-3xl`.
- **`layouts/auth.html.erb`** — strony publiczne (login). Bez navbaru, bez kontenera — pełen viewport. Używane przez `SessionsController#new` via `layout "auth", only: :new`.
- **`shared/_toast.html.erb`** — flash jako dismissable toast (zielony check / czerwony x), auto-dismiss 5s przez Stimulus `toast_controller.js`.
- **`shared/_breadcrumbs.html.erb`** — breadcrumbs wg Tailwind UI. Locals: `crumbs:` (tablica `[label, path]`, `path: nil` = current page), `home_path:` (domyślnie `root_path`, `host_root_path` na panel hosta).
- **`shared/_turbo_confirm.html.erb`** — `<el-dialog>` modal zastępujący natywny `confirm()` dla `data-turbo-confirm`. Stimulus `turbo_confirm_controller.js` w `connect()` podmienia `Turbo.config.forms.confirm` na ten dialog. Locals: `title:`, `message:`, `confirm_label:`, `cancel_label:`. Etykiety przycisków ASCII-only (PL znaki w defaults miewały problem z encodingiem).

**Tytuły stron** przez `content_for(:title)`:

```erb
<title><%= content_for?(:title) ? "#{content_for(:title)} — Gig Coordinator" : "Gig Coordinator" %></title>
```

Każdy widok ustawia własny: `<% content_for(:title) { @event.name } %>`.

---

# Widoki społecznościowe (user-facing)

Dwie listy dostępne z dropdown menu w navbarze, obie tylko dla zalogowanych **userów** (hosts → redirect na login):

- **`/pracownicy`** (`UsersController#index`, `users_path`) — lista wszystkich pracowników, sortowana po randze **desc** (Mistrz na górze → Nowy na dole), w obrębie rangi alfabetycznie. Pokazuje avatar + imię + **kolorowy badge rangi** + licznik 🐔 zaliczonych łapań (confirmed participations na eventach z `completed_at`). Liczniki z jednego dodatkowego `GROUP BY` query — zero N+1.

**Roster eventu (`_roster.html.erb`)** ma **cztery** sekcje: (1) Rezerwacje (indigo), (2) Potwierdzeni (emerald), (3) Rezerwa (amber), (4) **Wszyscy pracownicy** — neutralne szare wiersze ze WSZYSTKIMI userami w systemie, każdy z avatarem, badge'em rangi i statusem po prawej (`oczekuje` / `zapisany` / `rezerwa` / `anulował`) jeśli mają participation na tym evencie. W trzech górnych sekcjach rangę renderujemy pod imieniem. Jeden `User.with_attached_photo.order(title: :desc, last_name: :asc)` query + `index_by(&:user_id)` lookup uniemożliwia N+1.
- **`/organizatorzy`** (`HostsController#index`, `hosts_path`) — lista wszystkich organizatorów z avatarem, lokalizacją i licznikiem nadchodzących eventów.

---

# Animacje (Tailwind v4)

`app/assets/tailwind/application.css` rejestruje dwa keyframe'y w `@theme`:

- `animate-pop-in` — fade + translate-y + scale (350ms, cubic-bezier) — używane na badge'ach, roster `<li>` (staggered `animation-delay: i*40ms`).
- `animate-bump` — pulse scale 1→1.15→1 (450ms) — liczniki (`_counts.html.erb`) przy każdym broadcaście.

Button press: `transition-transform active:scale-[0.97]` na przyciskach akceptacji/anulowania.

---

# PWA

Manifest + service worker serwowane natywnie przez **`Rails::PwaController`** (wbudowany w railties). Routes:

```ruby
get "manifest"       => "rails/pwa#manifest",       as: :pwa_manifest,       defaults: { format: :json }
get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }
```

`Rails::PwaController` dziedziczy z `ActionController::Base` (nie z naszego `ApplicationController`), więc `allow_browser :modern` go nie dotyczy — klienci bez User-Agent dostają prawdziwy JSON/JS, nie HTML-a z „upgrade browser". Widoki w `app/views/pwa/manifest.json.erb` + `app/views/pwa/service-worker.js`. Layout linkuje `pwa_manifest_path`; Stimulus push rejestruje `/service-worker`.

**Ikony** generowane z `public/icon.svg` (pixel-art kura, 20×20 viewBox, `shape-rendering: crispEdges`) przez `rsvg-convert`:

```bash
rsvg-convert -w 192 -h 192 public/icon.svg -o public/icon-192.png
rsvg-convert -w 512 -h 512 public/icon.svg -o public/icon-512.png
rsvg-convert -w 180 -h 180 public/icon.svg -o public/apple-touch-icon.png
rsvg-convert -w 32  -h 32  public/icon.svg -o public/favicon-32.png
rsvg-convert -w 512 -h 512 public/icon.svg -o public/icon.png   # backward-compat
```

Regeneruj po edycji `icon.svg`.

---

# Dev port

`config/environments/development.rb` czyta `ENV["PORT"]` (fallback 3000) gdy `PUBLIC_HOST` nie jest ustawiony — magic-link URL-e idą na właściwy port. `bin/login-link` tak samo. Jeśli trzymasz kilka Rails apek lokalnie, eksportuj `PORT=3001 bin/dev` (i `PORT=3001 bin/login-link ...`) żeby link wygenerował się z portem 3001.

---

# Dev tunnel (mobile testing)

iOS web push wymaga HTTPS + PWA z Home Screen.

```bash
cloudflared tunnel --url http://localhost:3000                # Terminal 1
PUBLIC_HOST=<tunnel>.trycloudflare.com bin/dev                # Terminal 2
PUBLIC_HOST=<tunnel>.trycloudflare.com bin/login-link <email> # wygeneruj link
```

`config/environments/development.rb` whitelistuje `*.trycloudflare.com`, `*.ngrok-free.app`, `*.ngrok.io`, `*.lhr.life`, `*.localhost.run`, `*.serveo.net` (przez `config.hosts`), wyłącza `action_cable.request_forgery_protection`, i nadpisuje `default_url_options` na `https://<PUBLIC_HOST>` gdy env var jest ustawiony.

---

# Testy

- `test/support/auth_helpers.rb` → `sign_in_as(record)` dla integration + system (robi prawdziwy request do `/logowanie/weryfikacja`).
- System testy w `test/system/`, `driven_by :selenium, using: :headless_chrome, screen_size: [390, 844]` (mobilny viewport).
- Turbo Stream broadcasty są synchroniczne → testy nie potrzebują `perform_enqueued_jobs`.
- Mailer + `WebPushNotifier` są async → `assert_enqueued_emails` / `assert_enqueued_with(job: WebPushNotifier)`.
- Dla logiki modelu: `Participation.create!(..., status:, position:)` bezpośrednio, bez kontrolera.
