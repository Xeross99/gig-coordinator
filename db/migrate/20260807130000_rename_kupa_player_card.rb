# Karta gracza „kupa" dostała neutralny klucz `kurnik` (scena przedstawia kurę
# przed kurnikiem). Klucz jest walidowany przez inclusion w User::PLAYER_CARDS
# i wskazuje na plik app/assets/images/player_cards/<klucz>.svg — bez przepisania
# istniejących wierszy taki user miałby nieważną wartość i 404 na tle.
class RenameKupaPlayerCard < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE users SET player_card = 'kurnik' WHERE player_card = 'kupa'"
  end

  def down
    execute "UPDATE users SET player_card = 'kupa' WHERE player_card = 'kurnik'"
  end
end
