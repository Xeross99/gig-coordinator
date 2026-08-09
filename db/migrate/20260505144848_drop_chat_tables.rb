class DropChatTables < ActiveRecord::Migration[8.1]
  def change
    drop_table :campaign_messages do |t|
      t.references :event_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :user,           null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
      t.index %i[event_campaign_id created_at]
    end

    drop_table :messages do |t|
      t.text :body, null: false
      t.references :event, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.timestamps
      t.index %i[event_id created_at]
    end

    remove_column :events,          :messages_count, :integer, default: 0, null: false
    remove_column :event_campaigns, :messages_count, :integer, default: 0, null: false
  end
end
