class FixQuickUndoArtifact < ActiveRecord::Migration[8.1]
  # Test artefakt: po accepted → cancelled programista re-joinował i wycofał
  # się 2 sekundy później, sztucznie wygrywając „Klikam i Cofam". Rozsuwam
  # odstęp do 5 minut — to wciąż szybko, ale w granicach realnej decyzji
  # człowieka, więc nie dominuje rankingu.
  def up
    # Jednorazowa korekta danych konkretnego konta. Adres nie jest zaszyty w
    # repo (publiczne) — bez ENV migracja jest no-opem, co jest właściwe:
    # na świeżej bazie nie ma czego poprawiać.
    email = ENV["QUICK_UNDO_FIX_EMAIL"]
    return if email.blank?

    user = User.find_by(email: email)
    return unless user

    # Cel: ostatni cancelled w historii participation którego poprzednikiem
    # był joined w odstępie < 30s (tylko taki przypadek tu mamy).
    pid = ParticipationEvent.joins(:participation)
                            .where(participations: { user_id: user.id }, event_type: :cancelled)
                            .order("participation_events.created_at DESC")
                            .limit(1)
                            .pluck(:participation_id)
                            .first
    return unless pid

    history = ParticipationEvent.where(participation_id: pid).order(:created_at).to_a
    last_cancelled = history.last
    prior = history[-2]
    return unless last_cancelled&.cancelled? && prior&.joined?

    delta = last_cancelled.created_at - prior.created_at
    return if delta >= 30   # już po ludzku; nic nie ruszamy

    new_at = prior.created_at + 5.minutes
    last_cancelled.update_columns(created_at: new_at)
    Participation.where(id: pid).update_all(updated_at: new_at)
  end

  def down
    # No-op — sztuczne timestampy nieodwracalne.
  end
end
