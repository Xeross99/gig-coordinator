class EventChange < ApplicationRecord
  belongs_to :event, counter_cache: :changes_count
  belongs_to :user, optional: true

  # Pola, które logujemy. Reszta `saved_changes` (timestampy, completed_at,
  # bookkeeping) jest ignorowana, bo nie jest interesująca dla user'a.
  TRACKED_FIELDS = %w[name host_id scheduled_at ends_at pay_per_person capacity].freeze
end
