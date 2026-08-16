class Event < ApplicationRecord
  include Fillable, Campaignable, Reservable, Notifiable, Broadcastable, Auditable, Rosterable

  belongs_to :host
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :event_campaign, optional: true

  has_many :participations, dependent: :destroy
  has_many :users, through: :participations
  has_many :carpool_offers, dependent: :destroy
  has_many :carpool_requests, through: :carpool_offers
  has_many :changes_log, class_name: "EventChange", dependent: :destroy
  has_many :swap_proposals, dependent: :destroy

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true
  validates :scheduled_at, :ends_at, presence: true
  validates :pay_per_person, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate  :ends_at_after_scheduled_at

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :awaiting_completion, -> { where("ends_at < ? AND completed_at IS NULL", Time.current) }
  scope :past, -> { where("scheduled_at <= ?", Time.current).order(scheduled_at: :desc) }

  def to_param
    slug = name.to_s.parameterize
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def completed?
    completed_at.present?
  end

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
