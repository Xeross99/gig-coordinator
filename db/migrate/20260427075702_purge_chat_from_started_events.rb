class PurgeChatFromStartedEvents < ActiveRecord::Migration[8.1]
  # Backfill „event-locked → chat wiped". Od tej pory `EventChatPurgeJob` kasuje
  # wiadomości w momencie scheduled_at, ale wszystkie eventy które już ruszyły
  # przed wdrożeniem tej zmiany mają wciąż swój czat — wycinamy go jednym
  # zapytaniem.
  def up
    execute <<~SQL
      DELETE FROM messages
      WHERE event_id IN (
        SELECT id FROM events WHERE scheduled_at <= CURRENT_TIMESTAMP
      );
    SQL
  end

  def down
    # Nieodwracalne — kasujemy historyczne wiadomości bezpowrotnie.
  end
end
