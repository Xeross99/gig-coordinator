module Event::Capacity
  extend ActiveSupport::Concern

  # Filling the event: „Zapisz od razu" from the creation form, plus reacting to
  # the host moving `capacity` up or down after the fact.

  # Zapis od razu: virtual attribute set from the event-creation form. Handled
  # in-transaction (after_create, NOT after_create_commit) so the confirmed
  # participations exist before `seed_reservations` fires — `invite_candidates`
  # then naturally excludes them, which enforces "mistrz dodany od razu = brak
  # osobnej rezerwacji dla niego". Działa też na update — admin może dorzucić
  # ludzi do istniejącego eventu (np. po bumpie capacity 3→6).
  attr_accessor :pre_registered_user_ids

  included do
    after_create :process_pre_registrations
    after_update :process_pre_registrations

    # Muszą być OSTATNIE w łańcuchu after_update_commit: obie wołają
    # ReservationService → `event.lock!` → `reload`, co czyści `saved_changes`.
    # Wszystko, co je czyta (log historii, broadcast karty, push o zmianie),
    # musi zdążyć wcześniej — stąd `include Capacity` na końcu listy w event.rb.
    after_update_commit :refill_on_capacity_increase
    after_update_commit :demote_on_capacity_decrease
  end

  private

  def process_pre_registrations
    ids = Array(pre_registered_user_ids).map(&:to_i).uniq.reject(&:zero?)
    return if ids.empty?

    blocked = HostBlock.where(host_id: host_id).pluck(:user_id).to_set
    # Mistrz Pióra zawsze idzie przez flow zaproszenia (rezerwacja + accept/decline),
    # nawet jeśli ktoś zaznaczy go w „Zapisz od razu". Po pominięciu ich tutaj
    # `seed_reservations` (after_create_commit) złapie ich jako kandydatów do
    # invite_candidates i wyśle zaproszenie.
    mistrz_ids = User.mistrz_piora.where(id: ids).pluck(:id).to_set
    # Pomijamy istniejących uczestników (active + cancelled) — uniqueness
    # (event_id, user_id) i tak by uderzyła. Re-aktywacja anulowanego musi
    # iść normalnym torem (controller / konsola).
    existing_ids = participations.where(user_id: ids).pluck(:user_id).to_set
    ordered = ids.reject { |i| blocked.include?(i) || mistrz_ids.include?(i) || existing_ids.include?(i) }
    return if ordered.empty?

    users = User.where(id: ordered).index_by(&:id)
    open_slots = [ capacity - participations.holding_slot.count, 0 ].max
    confirmed_ids, waitlist_ids = ordered.first(open_slots), ordered.drop(open_slots)

    next_confirmed_pos = (participations.confirmed.maximum(:position) || 0) + 1
    next_waitlist_pos  = (participations.waitlist.maximum(:position)  || 0) + 1

    confirmed_ids.each_with_index do |uid, idx|
      next unless users[uid]
      participations.create!(user: users[uid], status: :confirmed, position: next_confirmed_pos + idx)
    end
    waitlist_ids.each_with_index do |uid, idx|
      next unless users[uid]
      participations.create!(user: users[uid], status: :waitlist, position: next_waitlist_pos + idx)
    end
  end

  # Host bumped capacity → promote from waitlist (or invite top-tier) to fill
  # the freshly-opened slots. No-op on decrease (handled by
  # `demote_on_capacity_decrease`) or on updates that don't touch capacity.
  def refill_on_capacity_increase
    return unless saved_change_to_capacity?
    old_cap, new_cap = saved_change_to_capacity
    return unless new_cap.to_i > old_cap.to_i
    ReservationService.fill_open_slots(self)
  end

  # Host shrunk capacity below the confirmed headcount → push the most-recently
  # confirmed users back onto the waitlist (front of the queue). No-op when
  # confirmed_count still fits inside the new capacity, or on capacity bumps.
  def demote_on_capacity_decrease
    return unless saved_change_to_capacity?
    old_cap, new_cap = saved_change_to_capacity
    return unless new_cap.to_i < old_cap.to_i
    ReservationService.demote_overflow(self)
  end
end
