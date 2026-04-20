class User < ApplicationRecord
  include Titleable

  # Presence is inferred from the throttled last_seen_at stamp written by
  # ApplicationController#touch_last_seen. Five minutes is a comfortable idle
  # window — covers page refreshes, scrolling, short tab-switches.
  ONLINE_WINDOW = 5.minutes

  has_many :participations, dependent: :destroy
  has_many :events, through: :participations
  has_many :push_subscriptions, dependent: :destroy
  has_many :sessions, as: :authenticatable, dependent: :destroy
  has_many :host_memberships, class_name: "HostManager", dependent: :destroy
  has_many :managed_hosts, -> { order(:last_name, :first_name) }, through: :host_memberships, source: :host

  has_one_attached :photo do |attachable|
    attachable.variant :small, resize_to_limit: [ 100, 100 ], format: "webp", saver: { quality: 88 }, preprocessed: true
  end

  normalizes :email, with: ->(v) { v.to_s.strip.downcase }

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  after_create_commit :send_welcome_email

  def display_name
    "#{first_name} #{last_name}"
  end

  def can_create_events?
    master? || (captain? && managed_hosts.exists?)
  end

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  end

  def send_welcome_email
    WelcomeMailer.notify(self).deliver_later
  end
end
