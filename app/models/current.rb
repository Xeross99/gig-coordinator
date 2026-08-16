class Current < ActiveSupport::CurrentAttributes
  attribute :session

  def host
    authenticatable_as(Host)
  end

  def user
    authenticatable_as(User)
  end

  private

  # Session is polymorphic — the same association holds a Host or a User, so
  # each accessor returns the record only when it is the type being asked for.
  def authenticatable_as(klass)
    record = session&.authenticatable
    record if record.is_a?(klass)
  end
end
