class Current < ActiveSupport::CurrentAttributes
  attribute :session

  def host
    session&.authenticatable if session&.authenticatable.is_a?(Host)
  end

  def user
    session&.authenticatable if session&.authenticatable.is_a?(User)
  end
end
