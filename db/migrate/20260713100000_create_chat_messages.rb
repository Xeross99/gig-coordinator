class CreateChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.text :body
      t.timestamps
    end
    add_index :chat_messages, :created_at

    create_table :chat_mentions do |t|
      t.references :chat_message, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :chat_mentions, [ :chat_message_id, :user_id ], unique: true
  end
end
