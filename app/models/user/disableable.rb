module User::Disableable
  extend ActiveSupport::Concern

  included do
    scope :enabled, -> { where(disabled_at: nil) }
  end

  def disabled?
    disabled_at.present?
  end

  def disable!
    transaction do
      update!(disabled_at: Time.current)
      sessions.destroy_all
      login_codes.delete_all
    end
  end

  def enable!
    update!(disabled_at: nil)
  end
end
