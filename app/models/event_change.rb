class EventChange < ApplicationRecord
  belongs_to :event, counter_cache: :changes_count
  belongs_to :user, optional: true

  TRACKED_FIELDS = %w[name host_id scheduled_at ends_at pay_per_person capacity].freeze
end
