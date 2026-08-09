class CreateEventCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :event_campaigns do |t|
      t.references :host,    null: false, foreign_key: true
      t.references :creator, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string     :name,           null: false
      t.integer    :capacity,       null: false
      t.integer    :messages_count, default: 0, null: false
      t.integer    :changes_count,  default: 0, null: false
      t.datetime   :completed_at
      t.timestamps
    end
  end
end
