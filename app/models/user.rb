class User < ApplicationRecord
  has_many :participations, dependent: :destroy
  has_many :events, through: :participations
  has_many :push_subscriptions, dependent: :destroy
  has_many :sessions, as: :authenticatable, dependent: :destroy

  has_one_attached :photo do |attachable|
    attachable.variant :roster, resize_to_fill: [ 40, 40 ]
  end

  enum :title, { rookie: 0, member: 1, veteran: 2, master: 3 }

  normalizes :email, with: ->(v) { v.to_s.strip.downcase }

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  def display_name
    "#{first_name} #{last_name}"
  end

  def display_title
    I18n.t("user.titles.#{title}", default: title.to_s.humanize)
  end

  TITLE_BADGE_COLORS = {
    "rookie"         => "bg-gray-100 text-gray-600",       # lowest
    "member"     => "bg-green-100 text-green-700",
    "veteran" => "bg-purple-100 text-purple-700",
    "master"       => "bg-yellow-100 text-yellow-800"    # highest (gold)
  }.freeze

  def title_badge_classes
    TITLE_BADGE_COLORS.fetch(title, "bg-gray-100 text-gray-600")
  end
end
