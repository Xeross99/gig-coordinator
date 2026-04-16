class Session < ApplicationRecord
  belongs_to :authenticatable, polymorphic: true

  before_validation :ensure_token, on: :create
  validates :token, presence: true, uniqueness: true

  private

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end
end
