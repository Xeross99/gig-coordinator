class AddIndexToParticipationEventsEventType < ActiveRecord::Migration[8.1]
  # Statystyki (/statystyki) filtrują audit-log po event_type w ~10 zapytaniach
  # agregujących — bez indeksu każde z nich skanuje całą tabelę.
  # `add_index` na SQLite NIE przebudowuje tabeli (bezpieczne — patrz CLAUDE.md).
  def change
    add_index :participation_events, :event_type
    add_index :campaign_participation_events, :event_type
  end
end
