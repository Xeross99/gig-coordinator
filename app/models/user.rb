class User < ApplicationRecord
  include Titleable, Premiumable, Calendarable, Disableable, Avatarable

  # Presence is inferred from the throttled last_seen_at stamp written by
  # Trackable#touch_last_seen. Five minutes is a comfortable idle
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

  normalizes :email, with: ->(v) { v.to_s.strip.downcase.presence }
  normalizes :phone, with: ->(v) { v.to_s.strip.presence }

  validates :last_name, presence: true
  validates :first_name, presence: true, uniqueness: { scope: :last_name, case_sensitive: false }
  validates :email, presence: true, uniqueness: { case_sensitive: true }, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  after_create_commit { WelcomeMailer.notify(self).deliver_later }

  after_update_commit :clear_host_blocks_on_mistrz_promotion, :send_rank_promotion_email, if: :saved_change_to_title?

  def display_name
    "#{first_name} #{last_name}"
  end

  def can_create_events?
    mistrz_piora? || (kurnikowy_komendant? && managed_hosts.exists?)
  end

  def event_creator_rank?
    mistrz_piora? || kurnikowy_komendant?
  end

  def allowed_hosts
    if admin? || mistrz_piora?
      Host.all
    elsif kurnikowy_komendant?
      managed_hosts
    else
      []
    end
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

  def can_manage_event?(event)
    return false if event.nil?
    return true if admin? || mistrz_piora?

    kurnikowy_komendant? && managed_hosts.exists?(id: event.host_id)
  end

  def can_join_events?
    !zoltodziob?
  end

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  end

  def blocked_from?(host)
    return false if host.nil?

    host_blocks.exists?(host_id: host.id)
  end

  def clear_host_blocks_on_mistrz_promotion
    return unless mistrz_piora?

    HostBlock.where(user_id: id).delete_all
  end

  def send_rank_promotion_email
    return unless email.present?

    prev_title, new_title = saved_change_to_title
    return if prev_title.blank?

    prev_idx = self.class.titles[prev_title]
    new_idx  = self.class.titles[new_title]
    return unless prev_idx && new_idx && new_idx > prev_idx

    RankPromotionMailer.notify(self, new_title: new_title).deliver_later
  end
end
