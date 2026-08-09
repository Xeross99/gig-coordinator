# Warstwa API pod aplikację mobilną została usunięta z kodu — tabele, które
# obsługiwała wyłącznie ona, lecą razem z nią:
#   * expo_push_tokens — tokeny Expo Push (rejestrowane tylko przez API)
#   * chat_messages / chat_mentions — czat był mobile-only, PWA nie ma dla niego UI
#
# Kolejność: chat_mentions ma FK na chat_messages, więc dziecko idzie pierwsze.
# disable_ddl_transaction! zgodnie z regułą projektu dla SQLite — poza transakcją
# PRAGMA foreign_keys = OFF faktycznie działa, więc DROP nie odpala niejawnych
# kaskad w tabelach powiązanych.
class DropMobileApiTables < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Zdjęcia z czatu wisiały na ChatMessage przez Active Storage. Po usunięciu
    # tabeli rekordy attachmentów byłyby sierotami wskazującymi na nieistniejący
    # typ — kasujemy je, a osierocone blob-y sprzątnie recurring
    # purge_unattached_active_storage_blobs.
    ActiveStorage::Attachment.where(record_type: "ChatMessage").delete_all

    drop_table :chat_mentions
    drop_table :chat_messages
    drop_table :expo_push_tokens
  end

  def down
    create_table :expo_push_tokens do |t|
      t.string :token
      t.string :tokenable_type
      t.integer :tokenable_id
      t.timestamps
    end
    add_index :expo_push_tokens, :token, unique: true
    add_index :expo_push_tokens, [ :tokenable_type, :tokenable_id ]

    create_table :chat_messages do |t|
      t.text :body
      t.integer :user_id, null: false
      t.timestamps
    end
    add_index :chat_messages, :created_at
    add_index :chat_messages, :user_id
    add_foreign_key :chat_messages, :users

    create_table :chat_mentions do |t|
      t.integer :chat_message_id, null: false
      t.integer :user_id, null: false
      t.timestamps
    end
    add_index :chat_mentions, [ :chat_message_id, :user_id ], unique: true
    add_index :chat_mentions, :chat_message_id
    add_index :chat_mentions, :user_id
    add_foreign_key :chat_mentions, :chat_messages
    add_foreign_key :chat_mentions, :users
  end
end
