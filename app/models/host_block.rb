class HostBlock < ApplicationRecord
  belongs_to :user
  belongs_to :host

  validates :user_id, uniqueness: { scope: :host_id }
  validate :user_is_not_mistrz_piora

  private

  def user_is_not_mistrz_piora
    return unless user&.mistrz_piora?

    errors.add(:user, "nie może być Mistrzem Pióra — ta ranga nie podlega blokadom")
  end
end
