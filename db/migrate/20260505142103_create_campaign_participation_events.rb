class CreateCampaignParticipationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_participation_events do |t|
      t.references :campaign_participation, null: false, foreign_key: { on_delete: :cascade }, index: { name: "idx_cpe_on_campaign_participation_id" }
      t.integer    :event_type, null: false
      t.datetime   :created_at, null: false
    end
  end
end
