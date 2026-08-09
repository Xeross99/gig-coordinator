# Usunięcie pracownika wywalało FOREIGN KEY constraint (500), gdy user
# stworzył jakiś event albo był aktualnie odbieranym pasażerem podwózki.
# Te kolumny są opcjonalne (belongs_to optional / sentinel) — przy kasowaniu
# usera mają się wyzerować, jak już zrobione dla event_campaigns.creator_id
# i event_changes.user_id.
class NullifyUserReferencesOnDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :events, column: :creator_id
    add_foreign_key :events, :users, column: :creator_id, on_delete: :nullify

    remove_foreign_key :carpool_offers, column: :current_pickup_user_id
    add_foreign_key :carpool_offers, :users, column: :current_pickup_user_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :events, column: :creator_id
    add_foreign_key :events, :users, column: :creator_id

    remove_foreign_key :carpool_offers, column: :current_pickup_user_id
    add_foreign_key :carpool_offers, :users, column: :current_pickup_user_id
  end
end
