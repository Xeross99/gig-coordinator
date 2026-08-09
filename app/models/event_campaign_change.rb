class EventCampaignChange < ApplicationRecord
  belongs_to :event_campaign, counter_cache: :changes_count
  belongs_to :user, optional: true

  TRACKED_FIELDS = %w[name host_id capacity].freeze
end
