class Event < ApplicationRecord
  # UWAGA: kolejność include'ów = kolejność rejestracji callbacków, a ta jest
  # tu częścią kontraktu — `Capacity` musi być OSTATNI, bo jego callbacki robią
  # `reload` i czyszczą `saved_changes` czytane przez `ChangeLog`, `Broadcasting`
  # i `Notifications`. Osobne linie, nie `include A, B, C` — przy liście przez
  # przecinek Ruby włącza moduły od końca i callbacki zarejestrowałyby się
  # w odwrotnej kolejności.
  include Roster
  include ChangeLog
  include Broadcasting
  include Notifications
  include Reservations
  include SubEvent
  include Capacity

  belongs_to :host
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :event_campaign, optional: true
  has_many :participations, dependent: :destroy
  has_many :users, through: :participations
  has_many :carpool_offers, dependent: :destroy
  has_many :carpool_requests, through: :carpool_offers
  has_many :changes_log, class_name: "EventChange", dependent: :destroy
  has_many :swap_proposals, dependent: :destroy

  # Strip nazwy — inaczej „2 auta " (trailing space z API create, które nie
  # przycinało params[:name]) vs. „2 auta" z edycji renderowałoby się w historii
  # jako fałszywa zmiana „2 auta → 2 auta" (i wysyłało push :event_changed).
  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true
  validates :scheduled_at, :ends_at, presence: true
  validates :pay_per_person, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate  :ends_at_after_scheduled_at

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :awaiting_completion, -> { where("ends_at < ? AND completed_at IS NULL", Time.current) }
  # „Wykonane" w UI: wszystko od momentu startu — w trakcie (started, brak completed_at)
  # i już zakończone. EventCompletionJob nie odpala się natychmiast po ends_at, więc
  # filtrowanie tylko po `completed_at` zostawiało dziurę: event w trakcie nie był
  # ani w upcoming, ani w „Wykonane".
  scope :past, -> { where("scheduled_at <= ?", Time.current).order(scheduled_at: :desc) }

  def to_param
    slug = name.to_s.parameterize
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def completed?
    completed_at.present?
  end

  # Event jest „zablokowany" od momentu startu — żadnych zmian w roster, kierowcach,
  # pasażerach, czacie. Predykat działa też dla eventów już zakończonych
  # (`completed?`), więc lock obowiązuje od scheduled_at na zawsze.
  def started?
    scheduled_at.present? && scheduled_at <= Time.current
  end

  private

  def ends_at_after_scheduled_at
    return if ends_at.blank? || scheduled_at.blank?
    errors.add(:ends_at, :must_be_after_start) if ends_at <= scheduled_at
  end

  def upcoming_now?
    scheduled_at.present? && scheduled_at > Time.current
  end
end
