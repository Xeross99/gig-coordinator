class BackfillJoinedWaitlistEvents < ActiveRecord::Migration[8.1]
  # Splits the legacy `joined` event_type (0) into two granular flavours so the
  # history timeline can show different visuals for "wszedł od razu na listę
  # główną" vs "wskoczył na rezerwę". Updates rows where we can infer the
  # original target status:
  #   * a later `:promoted` event for the same participation → was a waitlist join
  #   * the participation is currently on the waitlist           → was a waitlist join
  # Anything else stays as `:joined` (= confirmed) — best-effort, we never had
  # the target status persisted before.
  def up
    execute <<~SQL
      UPDATE participation_events
      SET event_type = 7
      WHERE event_type = 0
        AND (
          EXISTS (
            SELECT 1 FROM participation_events later
            WHERE later.participation_id = participation_events.participation_id
              AND later.event_type = 5
              AND later.created_at > participation_events.created_at
          )
          OR EXISTS (
            SELECT 1 FROM participations p
            WHERE p.id = participation_events.participation_id
              AND p.status = 1
          )
        );
    SQL
  end

  def down
    execute "UPDATE participation_events SET event_type = 0 WHERE event_type = 7;"
  end
end
