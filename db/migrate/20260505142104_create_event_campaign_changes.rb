class CreateEventCampaignChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :event_campaign_changes do |t|
      t.references :event_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :field,          null: false
      t.string :previous_value
      t.string :new_value
      t.timestamps
    end

    add_index :event_campaign_changes, %i[event_campaign_id created_at],
              name: "index_campaign_changes_on_campaign_and_created_at"
  end
end
