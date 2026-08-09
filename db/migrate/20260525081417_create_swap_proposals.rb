class CreateSwapProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :swap_proposals do |t|
      t.references :event,    null: false, foreign_key: true
      t.references :proposer, null: false, foreign_key: { to_table: :users }
      t.references :target,   null: false, foreign_key: { to_table: :users }
      t.integer    :status,   null: false, default: 0
      t.datetime   :expires_at

      t.timestamps
    end

    add_index :swap_proposals, %i[event_id proposer_id target_id],
              unique: true,
              where: "status = 0",
              name: "idx_swap_proposals_pending_unique"
    add_index :swap_proposals, %i[event_id target_id status],
              name: "idx_swap_proposals_target_lookup"
    add_index :swap_proposals, :expires_at
  end
end
