class Host < ApplicationRecord
  include Avatarable

  has_many :events, dependent: :destroy
  has_many :sessions, as: :authenticatable, dependent: :destroy
  has_many :host_managers, dependent: :destroy
  has_many :managers, through: :host_managers, source: :user

  normalizes :email, with: ->(v) { v.to_s.strip.downcase.presence }
  normalizes :phone, with: ->(v) { v.to_s.strip.presence }

  validates :last_name, :location, presence: true
  validates :first_name, presence: true, uniqueness: { scope: :last_name, case_sensitive: false }

  validates :email, uniqueness: { case_sensitive: false, allow_blank: true },
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  def display_name
    "#{first_name} #{last_name}"
  end
end
