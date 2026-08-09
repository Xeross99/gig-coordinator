class AddEventCampaignToEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :event_campaign, foreign_key: { on_delete: :cascade }, null: true
  end
end
