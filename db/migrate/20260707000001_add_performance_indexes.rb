class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Wzorzec `event_campaign_id = ? AND scheduled_at > ?` — feed (karty kampanii,
    # campaign_sort_keys, scope EventCampaign.active) i kaskady kampanii
    # (enroll_in_sub_events / cancel_on_sub_events).
    add_index :events, [ :event_campaign_id, :scheduled_at ]
    # Filtry „wykonane": Event.past / awaiting_completion, catch-counts na
    # /pracownicy, EventCampaign.completed/.active.
    add_index :events, :completed_at
    add_index :event_campaigns, :completed_at
  end
end
