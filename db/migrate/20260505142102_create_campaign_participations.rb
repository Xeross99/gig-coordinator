class CreateCampaignParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_participations do |t|
      t.references :event_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :user,           null: false, foreign_key: true
      t.integer    :status,         default: 0, null: false
      t.integer    :position,       default: 0, null: false
      t.datetime   :reserved_until
      t.timestamps
    end

    add_index :campaign_participations, %i[event_campaign_id user_id],
              unique: true,
              name: "index_campaign_participations_on_campaign_and_user"
    add_index :campaign_participations, %i[event_campaign_id status position],
              name: "index_campaign_participations_on_campaign_status_position"
    add_index :campaign_participations, :reserved_until
  end
end
