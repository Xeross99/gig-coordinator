class Host < ApplicationRecord
  has_many :events, dependent: :destroy
  has_many :sessions, as: :authenticatable, dependent: :destroy
  has_one_attached :photo do |attachable|
    attachable.variant :small,
                       resize_to_limit: [ 100, 100 ],
                       format: "webp",
                       saver: { quality: 88 },
                       preprocessed: true
  end

  normalizes :email, with: ->(v) { v.to_s.strip.downcase }

  validates :first_name, :last_name, :location, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  after_create_commit :send_welcome_email

  def display_name
    "#{first_name} #{last_name}"
  end

  private

  def send_welcome_email
    WelcomeMailer.with(record: self).notify.deliver_later
  end
end
