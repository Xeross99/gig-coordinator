class Host < ApplicationRecord
  has_many :events, dependent: :destroy
  has_many :sessions, as: :authenticatable, dependent: :destroy
  has_one_attached :photo

  normalizes :email, with: ->(v) { v.to_s.strip.downcase }

  validates :first_name, :last_name, :location, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  def display_name
    "#{first_name} #{last_name}"
  end
end
