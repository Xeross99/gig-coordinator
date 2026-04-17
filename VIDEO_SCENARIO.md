# Scenariusz wideo — „Gig Coordinator"

**Czas ~5 min. Dwa ekrany obok siebie:** po lewej telefon usera (PWA, 390×844), po prawej — laptop hosta. Narracja po polsku, w pierwszej osobie.

---

## Scena 1 — Otwarcie (0:00–0:20)

**Pokazujesz:** ekran startowy telefonu z ikoną kury („Gig Coordinator").
**Mówisz:** „Cześć. To Gig Coordinator — moja apka do łapania kur. Organizatorzy wrzucają zlecenia, a my, pracownicy, chodzimy je robić. Odpalam z pulpitu."

Klikasz ikonę → otwiera się jak natywna apka (PWA, bez paska adresu).

---

## Scena 2 — Logowanie magic-linkiem (0:20–0:50)

**Pokazujesz:** ekran `/logowanie`.
**Mówisz:** „Zero haseł do zapamiętywania. Wpisuję maila i dostaję linka — klikam i jestem w środku."

- Wpisujesz `admin@gigcoordinator.pl`
- Klikasz „Wyślij link logowania" → zielony toast: „Jeśli adres jest w systemie, wysłaliśmy link logowania"
- (Cut do skrzynki lub pokaż w logu `bin/dev`) klikasz linka → jesteś zalogowany na `/`

---

## Scena 3 — Feed + profil (0:50–1:30)

**Pokazujesz:** feed `/` — lista nadchodzących eventów, navbar z avatarem.
**Mówisz:** „Tu mam ogłoszenia — wszystko co nadchodzi. W rogu widać mnie z moją rangą."

Wskazujesz żółty badge **Mistrz** pod imieniem.

- Klikasz „Menu" → rozwija się dropdown (Tailwind Plus)
- Pokazujesz: **Mój profil**, **Wszyscy pracownicy**, **Wszyscy organizatorzy**, **Wyloguj**
- Klikasz **Wszyscy pracownicy** → lista rankingowa

**Mówisz:** „Tu cała ekipa. Na górze najlepsi — Mistrze Pióra, na dole świeżaki — Żółtodzioby. Każdy ma swoją kolorową plakietkę i licznik złapanych kur."

Krótki przejazd po liście: złote (Mistrz), fioletowe (Weteran), zielone (Członek), szare (Nowy).

- Wracasz do feedu
- Klikasz **Wszyscy organizatorzy** → lista hostów z lokalizacjami
- Wracasz

---

## Scena 4 — Organizator tworzy event, user jest „wciągany" (1:30–2:30)

**Teraz przełączasz się na drugi ekran (laptop hosta).**

**Mówisz:** „Teraz organizator Jan wrzuca nowe zlecenie — wydarzenie w środę rano, czwórka ludzi potrzebna."

- Host wypełnia formularz (`/panel/eventy/new`): nazwa, data, godziny, stawka 150 zł, 4 miejsca
- Kliknięcie **Utwórz event**

**Pokazujesz oba ekrany jednocześnie — telefon usera reaguje sam:**

- Na telefonie bez F5 następuje automatyczne przejście na stronę nowego eventu
- Banner **„Zostałeś zaproszony!"** z indigo gradientem, spinnerem i 1-godzinnym deadlinem
- Dwa przyciski: **Akceptuję** (czarny) / **Odrzuć** (białe obramowanie)

**Mówisz:** „Jestem Mistrzem Pióra, więc apka sama łapie mi miejsce. Mam godzinę, żeby się zdecydować. I zobacz — nic nie kliknąłem, telefon sam mnie tu przeniósł."

---

## Scena 5 — Akceptacja rezerwacji (2:30–3:10)

**Pokazujesz:** klikasz **Akceptuję**.

- Szybka animacja (`animate-pop-in`) → zielony badge **Potwierdzony**
- Na dole roster: sekcja **Potwierdzeni (1/4)** — Ty z avatarem i żółtym badge'em Mistrz
- Sekcja **Rezerwacje** znika

**Mówisz:** „Idę w to. Miejsce zaklepane. Na dole widać kto już jest zapisany, kto się jeszcze zastanawia, kto czeka w kolejce, a na końcu cała ekipa — kto ma jakiego statusa."

Pokazujesz scroll po sekcji **Wszyscy pracownicy** — userzy posortowani po randze, obok każdego status per event (oczekuje / zapisany / rezerwa / pusty).

---

## Scena 6 — Live roster z drugiego telefonu (3:10–3:50)

**Pokazujesz:** drugi telefon (albo drugie okno przeglądarki) — inny user, niższa ranga, np. Weteran.

**Mówisz:** „To drugi kolega, niższa ranga. On rezerwacji nie dostał — musi się sam zgłosić z listy."

- Otwiera event z feedu
- Klika **Akceptuję**
- Bez F5 roster pierwszego telefonu się odświeża: **Potwierdzeni (2/4)**, druga osoba dochodzi z animacją

**Mówisz:** „Widzisz? Lista u mnie odświeżyła się sama, nic nie klikałem."

Powtarzasz z trzecim i czwartym userem, aż event zapełniony: **Potwierdzeni (4/4)**.

---

## Scena 7 — Waitlist (3:50–4:20)

**Pokazujesz:** piąty user próbuje dołączyć do pełnego eventu.

- Klika **Akceptuję**
- Komunikat: **„Jesteś na liście rezerwowej"** (amber), pozycja 1

**Mówisz:** „Miejsca zajęte, więc kolega ląduje w kolejce. Jak ktoś się wykruszy — awansuje sam, bez robienia nic."

Pokazujesz: jeden z potwierdzonych klika **Anuluj** → custom modal z pytaniem „Czy na pewno?" → Potwierdzam → waitlister natychmiast awansuje na confirmed (live update obu ekranów).

---

## Scena 8 — Odrzucenie rezerwacji (4:20–4:50)

**Opcjonalna scena** — jeśli chcesz pokazać `refill_one`.

Na nowym evencie (inna demo) **Mistrz klika Odrzuć**:

- Modal potwierdzenia → Odrzucam
- Toast: „Odrzucone. Slot poszedł do następnego w kolejce"
- Jeśli jest inny user z najwyższą rangą → on dostaje nową rezerwację z 1h deadline
- Jeśli nie — slot zostaje pusty (nie schodzimy na niższą rangę)

---

## Scena 9 — Push notifications (4:50–5:10)

**Pokazujesz:** telefon zablokowany.

**Mówisz:** „I jeszcze jedno — jak organizator coś wrzuci albo dostanę zaproszenie, telefon mi dzwoni nawet jak jest zablokowany."

Organizator tworzy event → na telefonie pojawia się lock-screen notification z ikoną kury. Stuk w nią → otwiera event.

---

## Scena 10 — Outro (5:10–5:30)

**Pokazujesz:** feed z kilkoma eventami.

**Mówisz:** „No i tyle. Logujesz się jednym kliknięciem, najlepsi dostają pierwszeństwo, wszystko dzieje się na żywo, a telefon daje znać kiedy coś nowego. Dzięki za obejrzenie, trzymaj się!"

Fade do logo aplikacji.

---

## Checklist techniczny przed nagraniem

- [ ]  Odpal `bin/rails db:seed` żeby mieć świeży stan (Jan Kowalski + 6 userów z rangami)
- [ ]  Zaloguj Michała (`master`) na główny telefon, Mateusza lub Marcina na drugi
- [ ]  Host na laptopie zalogowany jako Jan Kowalski
- [ ]  Wyczyść eventy z DB przed sceną 4 (żeby live create był widoczny)
- [ ]  Push notifications: zainstaluj PWA na prawdziwym telefonie (wymaga HTTPS — użyj `cloudflared tunnel`)
- [ ]  Ustaw telefon na trybie zarezerwowanym do demo (tylko WiFi, wyłączone powiadomienia z innych apek)
- [ ]  Opcjonalnie: nagraj drugim ujęciem sam screencast z telefonu (QuickTime + kabel iPhone)
