module Event::Auditable
  extend ActiveSupport::Concern

  # Audit trail of field edits (`event_changes`), rendered on /eventy/:id/historia.

  # Ustawiane przez kontroler tuż przed zapisem — żeby `log_changes` umiał wpisać
  # autora edycji do EventChange.user_id. Na nowych eventach zostawiamy nil.
  attr_accessor :edited_by

  included do
    # Musi lecieć przed `broadcast_feed_replace` — karta w feedzie pokazuje
    # licznik historii, więc wpisy muszą już siedzieć w bazie.
    after_update_commit :log_changes
  end

  # Liczba pozycji jakie pojawią się na stronie historii. Musi być spójna
  # z `EventsController#build_history_entries`: 1 wpis „utworzono" + jeden wpis
  # per ParticipationEvent (audit log) + zmiany pól z `changes_log`.
  def history_count
    1 + ParticipationEvent.joins(:participation).where(participations: { event_id: id }).count + changes_count
  end

  private

  # Zapisuje wpis do `event_changes` per zmienione pole z TRACKED_FIELDS.
  # `edited_by` ustawia kontroler — gdy nil (callback z konsoli, jobów itd.),
  # log idzie z user_id = nil.
  def log_changes
    significant_changed_fields.each do |field|
      prev_v, new_v = saved_changes[field]
      changes_log.create!(
        user:           edited_by,
        field:          field,
        previous_value: prev_v.to_s,
        new_value:      new_v.to_s
      )
    end
  end

  # Pola z TRACKED_FIELDS, które faktycznie się zmieniły — z pominięciem różnic
  # kosmetycznych w białych znakach (np. „2 auta " → „2 auta"), które w historii
  # renderowałyby się jako identyczne „przed → po". Wspólne dla logu i pusha,
  # żeby oba widziały tę samą listę zmian.
  def significant_changed_fields
    EventChange::TRACKED_FIELDS.select do |field|
      next false unless saved_changes.key?(field)
      prev_v, new_v = saved_changes[field]
      prev_v.to_s.strip != new_v.to_s.strip
    end
  end
end
