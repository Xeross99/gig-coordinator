class CreateHostBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :host_blocks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :host, null: false, foreign_key: true, index: false
      t.timestamps
    end
    add_index :host_blocks, [ :user_id, :host_id ], unique: true
    add_index :host_blocks, [ :host_id, :user_id ]
  end
end
