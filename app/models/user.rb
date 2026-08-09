class User < ApplicationRecord
  include Titleable, Avatarable

  # Presence is inferred from the throttled last_seen_at stamp written by
  # ApplicationController#touch_last_seen. Five minutes is a comfortable idle
  # window — covers page refreshes, scrolling, short tab-switches.
  ONLINE_WINDOW = 5.minutes

  has_many :participations, dependent: :destroy
  has_many :events, through: :participations
  has_many :campaign_participations, dependent: :destroy
  has_many :login_codes, as: :authenticatable, dependent: :delete_all
  has_many :carpool_offers, dependent: :destroy
  has_many :carpool_requests, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :sessions, as: :authenticatable, dependent: :destroy
  has_many :host_memberships, class_name: "HostManager", dependent: :destroy
  has_many :managed_hosts, -> { order(:last_name, :first_name) }, through: :host_memberships, source: :host
  has_many :host_blocks, dependent: :destroy
  has_many :blocked_hosts, -> { order(:last_name, :first_name) }, through: :host_blocks, source: :host
  has_many :swap_proposals_as_proposer, class_name: "SwapProposal", foreign_key: :proposer_id, dependent: :destroy
  has_many :swap_proposals_as_target, class_name: "SwapProposal", foreign_key: :target_id, dependent: :destroy

  # Karty gracza (tła profilu à la Call of Duty) — dostępne tylko dla kont
  # premium. Klucz = nazwa pliku w app/assets/images/player_cards/<klucz>.svg.
  # Flaga `premium` jest nadawana przez admina (checkbox w /kurolapacze/:id/edit)
  # albo z konsoli. Etykiety leżą w tym samym hashu co klucze — jako dwie osobne
  # struktury (lista tutaj + tłumaczenia w pl.yml) potrafiły się rozjechać przy
  # dodaniu karty.
  PLAYER_CARD_LABELS = {
    "traktor"   => "Kury na traktorze",
    "kontener"  => "Kontener pełen kur",
    "wakacje"   => "Wakacyjny luz",
    "ladowarka" => "Kura na ładowarce",
    "kosmos"    => "Kura w kosmosie",
    "kurnik"    => "Kura z gównem"
  }.freeze

  PLAYER_CARDS = PLAYER_CARD_LABELS.keys.freeze

  # Konto wyłączone przez admina: user nie dostaje żadnych powiadomień
  # (push, e-mail), nie dostaje auto-rezerwacji i nie może się zalogować
  # (kod logowania nie jest wydawany, aktywne sesje są ubijane przy
  # wyłączeniu). Dane i historia zostają nietknięte — to jest alternatywa
  # dla twardego kasowania konta.
  scope :enabled, -> { where(disabled_at: nil) }

  normalizes :email, with: ->(v) { v.to_s.strip.downcase.presence }
  normalizes :phone, with: ->(v) { v.to_s.strip.presence }
  normalizes :player_card, with: ->(v) { v.presence } # opcja „Brak tła" wysyła ""

  validates :player_card, inclusion: { in: PLAYER_CARDS }, allow_nil: true
  validates :last_name, presence: true
  validates :first_name, presence: true, uniqueness: { scope: :last_name, case_sensitive: false }
  validates :email, presence: true, uniqueness: { case_sensitive: true }, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  before_create :ensure_calendar_token
  before_save :clear_player_card_unless_premium

  after_create_commit :send_welcome_email
  after_update_commit :clear_host_blocks_on_mistrz_promotion
  after_update_commit :send_rank_promotion_email
  after_update_commit :notify_premium_granted

  def display_name
    "#{first_name} #{last_name}"
  end

  def disabled?
    disabled_at.present?
  end

  def disable!
    transaction do
      update!(disabled_at: Time.current)
      sessions.destroy_all           # natychmiastowe wylogowanie wszędzie
      login_codes.delete_all         # aktywny kod nie może posłużyć do wejścia
    end
  end

  def enable!
    update!(disabled_at: nil)
  end

  # Chwilowo tylko admin może tworzyć eventy — niezależnie od rangi.
  # Mistrz_piora / komendant nadal widzą UI rangowe, ale przycisk „Zaplanuj
  # Wpisy do feedu i przycisk „Zaplanuj zlecenie" są widoczne dla mistrza pióra
  # i komendantów którzy zarządzają przynajmniej jednym gospodarzem. Submit
  # jest tym samym gejtem — komendant po wejściu w formularz może go wysłać.
  def can_create_events?
    mistrz_piora? || (kurnikowy_komendant? && managed_hosts.exists?)
  end

  def event_creator_rank?
    mistrz_piora? || kurnikowy_komendant?
  end

  # Gospodarze, dla których user może tworzyć eventy/kampanie: admin i mistrz
  # pióra — wszyscy; komendant — tylko zarządzani (`managed_hosts`); reszta —
  # nikt. Jedno źródło prawdy dla EventsController i EventCampaignsController.
  def allowed_hosts
    return Host.all if admin? || mistrz_piora?
    return managed_hosts if kurnikowy_komendant?
    Host.none
  end

  # Kandydaci do „Zapisz od razu" (pre-registracja przy tworzeniu eventu /
  # kampanii). Mistrz Pióra zawsze idzie przez flow zaproszenia — nie pokazujemy
  # ich tutaj, bo i tak dostaną rezerwację automatycznie. `excluding:` pozwala
  # wykluczyć obecnych uczestników na edycji (uniqueness na (event_id, user_id)
  # i tak nie pozwoliłby dodać ich ponownie).
  def self.available_for_prereg(excluding: nil)
    scope = with_attached_photo.where.not(title: titles[:mistrz_piora])
    scope = scope.where.not(id: excluding) if excluding
    scope.order(title: :desc, last_name: :asc, first_name: :asc)
  end

  # Edycja / usunięcie istniejącego eventu. Mistrz Pióra i admin mogą wszystko;
  # komendant tylko eventy u gospodarzy z `managed_hosts` (te same, dla których
  # może w ogóle tworzyć).
  def can_manage_event?(event)
    return false if event.nil?
    return true if admin? || mistrz_piora?
    kurnikowy_komendant? && managed_hosts.exists?(id: event.host_id)
  end

  # Żółtodziób to rola obserwatora — przegląda eventy, ale się nie zapisuje
  # i nie jest zapraszany. Dopiero po awansie na kurzego pachołka (lub wyżej)
  # zaczyna brać udział w zleceniach.
  def can_join_events?
    !zoltodziob?
  end

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  end

  # Premium jest czasowe — admin nadaje je na PREMIUM_DURATION (rok), a my
  # weryfikujemy termin przy każdym odczycie. Admin ma premium z automatu.
  PREMIUM_DURATION = 1.year

  def premium?
    admin? || premium_active?
  end

  # Czy user ma własne, nadal ważne premium (bez adminowego bonusu).
  def premium_active?
    premium_until.present? && premium_until.future?
  end

  # Wirtualny boolean pod checkbox w formularzu adminowym: zaznaczenie nadaje
  # premium na rok od teraz, odznaczenie odbiera. Ponowny zapis formularza bez
  # zmiany stanu NIE przedłuża terminu (inaczej każdy „Zapisz" resetowałby rok).
  def premium
    premium_active?
  end

  def premium=(value)
    active = ActiveModel::Type::Boolean.new.cast(value)
    return if active == premium_active?
    self.premium_until = active ? PREMIUM_DURATION.from_now : nil
  end

  # Tło renderujemy tylko gdy konto NADAL jest premium — po odebraniu flagi
  # karta znika z UI natychmiast, a `clear_player_card_unless_premium` czyści
  # kolumnę przy najbliższym zapisie rekordu.
  def player_card?
    premium? && player_card.present?
  end

  def blocked_from?(host)
    return false if host.nil?
    host_blocks.exists?(host_id: host.id)
  end

  def send_welcome_email
    WelcomeMailer.notify(self).deliver_later
  end

  # Invariant: mistrz_piora nigdy nie ma HostBlocków. Gdy user zostaje promowany
  # (np. z konsoli: `u.update!(title: :mistrz_piora)`), czyścimy wszystkie
  # istniejące blokady — bez tego walidacja `HostBlock#user_is_not_mistrz_piora`
  # chroniłaby jedynie przed tworzeniem nowych, a stare zostawałyby „osierocone".
  def clear_host_blocks_on_mistrz_promotion
    return unless saved_change_to_title? && mistrz_piora?
    HostBlock.where(user_id: id).delete_all
  end

  # Każdy awans (przejście na wyższą rangę w hierarchii enuma) wysyła maila.
  # Degradacje są ciche — nie ma sensu witać kogoś, kto właśnie spadł niżej.
  # `saved_change_to_title` zwraca [poprzednia, nowa] wartość po zapisie; gdy
  # nowy index > poprzedni, to awans. Pierwsze ustawienie tytułu (np. seed,
  # console.create) ma `prev = nil` — wtedy nic nie wysyłamy, mail leci dopiero
  # przy realnej promocji.
  def send_rank_promotion_email
    return unless saved_change_to_title? && email.present?

    prev_title, new_title = saved_change_to_title
    return if prev_title.blank?

    prev_idx = self.class.titles[prev_title]
    new_idx  = self.class.titles[new_title]
    return unless prev_idx && new_idx && new_idx > prev_idx

    RankPromotionMailer.notify(self, new_title: new_title).deliver_later
  end

  # Nadanie (lub przedłużenie) premium dziękuje pushem — z każdej ścieżki zapisu
  # (checkbox admina w /kurolapacze/:id/edit, `rails console`). Odebranie premium
  # (`premium_until` → nil/przeszłość) jest ciche, stąd guard na `premium_active?`.
  def notify_premium_granted
    return unless saved_change_to_premium_until? && premium_active?

    WebPushNotifier.perform_later(:premium_granted, user_id: id)
  end

  # URL kalendarza (`/kalendarz/:token.ics`) jest tokenem dostępu — calendar apps
  # nie wysyłają cookies, więc anonimowy GET z poprawnym tokenem zwraca feed.
  # Regenerate unieważnia stary URL: po `regenerate_calendar_token!` calendar
  # subskrybowany pod starym adresem przestanie się synchronizować, dopóki user
  # nie wpisze nowego URL-a.
  def regenerate_calendar_token!
    update!(calendar_token: SecureRandom.hex(20))
  end

  private

  def ensure_calendar_token
    self.calendar_token ||= SecureRandom.hex(20)
  end

  # Invariant: kartę gracza może mieć tylko konto premium. Kontroler i tak nie
  # przepuszcza `player_card` od nie-premium, ale zapis z konsoli / serwisu
  # też ma trzymać spójność — odebranie premium zeruje wybraną kartę.
  def clear_player_card_unless_premium
    self.player_card = nil unless premium?
  end
end
