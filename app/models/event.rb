class Event < ApplicationRecord
  belongs_to :host
  has_many :participations, dependent: :destroy
  has_many :users, through: :participations

  validates :name, presence: true
  validates :scheduled_at, :ends_at, presence: true
  validates :pay_per_person, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate  :ends_at_after_scheduled_at

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :awaiting_completion, -> { where("ends_at < ? AND completed_at IS NULL", Time.current) }

  def completed?
    completed_at.present?
  end

  def confirmed_count
    participations.confirmed.count
  end

  def waitlist_count
    participations.waitlist.count
  end

  def full?
    confirmed_count >= capacity
  end

  private

  def ends_at_after_scheduled_at
    return if ends_at.blank? || scheduled_at.blank?
    errors.add(:ends_at, :must_be_after_start) if ends_at <= scheduled_at
  end
end
