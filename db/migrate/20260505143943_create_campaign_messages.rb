class CreateCampaignMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_messages do |t|
      t.references :event_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :user,           null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end

    add_index :campaign_messages, %i[event_campaign_id created_at]
  end
end
