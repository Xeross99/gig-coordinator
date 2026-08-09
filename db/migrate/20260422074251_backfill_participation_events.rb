class BackfillParticipationEvents < ActiveRecord::Migration[8.1]
  # One-off: seed a single :joined / :reserved row per existing participation so
  # the host "Historia zapisów" panel isn't empty for events that pre-date the
  # audit log. Uses `created_at` from the participation itself — closest thing
  # we have to the real join time without a full history.
  def up
    execute <<~SQL
      INSERT INTO participation_events (participation_id, event_type, created_at)
      SELECT id,
             CASE status
               WHEN 0 THEN 0  -- confirmed -> :joined
               WHEN 1 THEN 0  -- waitlist  -> :joined
               WHEN 3 THEN 2  -- reserved  -> :reserved
               ELSE 0         -- cancelled -> :joined (we know nothing about prior state)
             END,
             created_at
      FROM participations
      WHERE NOT EXISTS (
        SELECT 1 FROM participation_events pe WHERE pe.participation_id = participations.id
      );
    SQL
  end

  def down
    # No-op: can't tell backfilled rows from real ones without an extra column.
  end
end
