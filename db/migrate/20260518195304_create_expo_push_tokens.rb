class CreateExpoPushTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :expo_push_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token

      t.timestamps
    end
    add_index :expo_push_tokens, :token, unique: true
  end
end
