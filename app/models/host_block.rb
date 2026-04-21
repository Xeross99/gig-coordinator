class HostBlock < ApplicationRecord
  belongs_to :user
  belongs_to :host

  validates :user_id, uniqueness: { scope: :host_id }
  validate :user_is_not_master

  private

  def user_is_not_master
    return if user.nil?
    errors.add(:user, "nie może być Mistrzem Pióra — ta ranga nie podlega blokadom") if user.master?
  end
end
