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
  # `allow_blank: true` on format: presence already rejects a blank email, so this
  # avoids surfacing both "can't be blank" and "invalid format" on the same submit.
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  after_create_commit :send_welcome_email
  after_update_commit :clear_host_blocks_on_mistrz_promotion

  def display_name
    "#{first_name} #{last_name}"
  end

  def can_create_events?
    master? || (captain? && managed_hosts.exists?)
  end

  # Chwilowo tylko master może finalizować utworzenie eventu — komendanci
  # wchodzą w formularz, ale przycisk „Utwórz" jest zablokowany.
  def can_submit_events?
    master?
  end

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
end
