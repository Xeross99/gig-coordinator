# Premium przestaje być flagą na zawsze — admin nadaje je na rok, więc
# trzymamy termin ważności. Istniejące konta premium dostają rok od migracji.
class ConvertPremiumToTimestamp < ActiveRecord::Migration[8.1]
  # remove_column na SQLite przebudowuje tabelę przez DROP TABLE users.
  # W transakcji migracji `PRAGMA foreign_keys = OFF` jest no-opem, więc DROP
  # odpala ON DELETE SET NULL na wszystkich FK wskazujących na users
  # (events.creator_id itd.) i zeruje dane — tak straciliśmy twórców eventów
  # 9.07.2026. Bez transakcji PRAGMA działa i przebudowa jest bezpieczna.
  # Dotyczy KAŻDEJ migracji przebudowującej tabelę-rodzica FK (users,
  # event_campaigns — tam cascade skasowałby sub-eventy!).
  disable_ddl_transaction!

  def up
    add_column :users, :premium_until, :datetime
    execute "UPDATE users SET premium_until = datetime('now', '+1 year') WHERE premium = 1"
    remove_column :users, :premium
  end

  def down
    add_column :users, :premium, :boolean, default: false, null: false
    execute "UPDATE users SET premium = 1 WHERE premium_until IS NOT NULL AND premium_until > datetime('now')"
    remove_column :users, :premium_until
  end
end
