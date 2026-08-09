class AddNotesToEventsAndEventCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :notes, :text
    add_column :event_campaigns, :notes, :text
  end
end
