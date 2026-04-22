class User < ApplicationRecord
  include Titleable, Avatarable

  # Presence is inferred from the throttled last_seen_at stamp written by
  # ApplicationController#touch_last_seen. Five minutes is a comfortable idle
  # window — covers page refreshes, scrolling, short tab-switches.
  ONLINE_WINDOW = 5.minutes

  has_many :participations, dependent: :destroy
  has_many :events, through: :participations
  has_many :messages, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :sessions, as: :authenticatable, dependent: :destroy
  has_many :host_memberships, class_name: "HostManager", dependent: :destroy
  has_many :managed_hosts, -> { order(:last_name, :first_name) }, through: :host_memberships, source: :host
  has_many :host_blocks, dependent: :destroy
  has_many :blocked_hosts, -> { order(:last_name, :first_name) }, through: :host_blocks, source: :host

  normalizes :email, with: ->(v) { v.to_s.strip.downcase.presence }
  normalizes :phone, with: ->(v) { v.to_s.strip.presence }

  validates :last_name, presence: true
  validates :first_name, presence: true, uniqueness: { scope: :last_name, case_sensitive: false }
  validates :email, presence: true, uniqueness: { case_sensitive: true }, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  after_create_commit :send_welcome_email
  after_update_commit :clear_host_blocks_on_mistrz_promotion
  after_update_commit :send_rank_promotion_email

  def display_name
    "#{first_name} #{last_name}"
  end

  # Chwilowo tylko admin może tworzyć eventy — niezależnie od rangi.
  # Mistrz_piora / komendant nadal widzą UI rangowe, ale przycisk „Zaplanuj
  # wydarzenie" oraz /eventy/nowy są gejtowane flagą admina. Kiedy wrócimy do
  # rangowego gatingu, odkomentuj starą wersję poniżej i skasuj admin-only.
  def can_create_events?
    admin?
  end

  def can_submit_events?
    admin?
  end

  # def can_create_events?
  #   master? || (captain? && managed_hosts.exists?)
  # end
  #
  # # Chwilowo tylko master może finalizować utworzenie eventu — komendanci
  # # wchodzą w formularz, ale przycisk „Utwórz" jest zablokowany.
  # def can_submit_events?
  #   master?
  # end

  def event_creator_rank?
    master? || captain?
  end

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  end

  def blocked_from?(host)
    return false if host.nil?
    host_blocks.exists?(host_id: host.id)
  end

  def send_welcome_email
    WelcomeMailer.notify(self).deliver_later
  end

  # Invariant: master nigdy nie ma HostBlocków. Gdy user zostaje promowany
  # (np. z konsoli: `u.update!(title: :master)`), czyścimy wszystkie
  # istniejące blokady — bez tego walidacja `HostBlock#user_is_not_master`
  # chroniłaby jedynie przed tworzeniem nowych, a stare zostawałyby „osierocone".
  def clear_host_blocks_on_mistrz_promotion
    return unless saved_change_to_title? && master?
    HostBlock.where(user_id: id).delete_all
  end

  # Auto-awans: przy każdej zmianie tytułu, jeśli nowy tytuł jest na liście
  # `RankPromotionMailer::NOTIFIABLE_TITLES` (komendant / master), leci
  # mail. Guard na `saved_change_to_title?` zapewnia, że nie wyślemy maila,
  # gdy user update'uje tylko np. zdjęcie profilowe albo email.
  def send_rank_promotion_email
    return unless saved_change_to_title? && email.present?

    new_title = title.to_s
    return unless RankPromotionMailer::NOTIFIABLE_TITLES.include?(new_title)

    RankPromotionMailer.notify(self, new_title: new_title).deliver_later
  end
end
