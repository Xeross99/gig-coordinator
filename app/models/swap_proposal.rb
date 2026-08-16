class SwapProposal < ApplicationRecord
  include Expirable

  belongs_to :event
  belongs_to :proposer, class_name: "User"
  belongs_to :target, class_name: "User"

  enum :status, { pending: 0, accepted: 1, declined: 2, expired: 3 }

  validates :proposer_id, uniqueness: {
    scope: %i[event_id target_id],
    conditions: -> { where(status: :pending) },
    message: "ma już oczekującą propozycję wymiany dla tej osoby"
  }

  validate :proposer_must_be_on_waitlist, on: :create
  validate :target_must_be_confirmed, on: :create
  validate :proposer_cannot_be_target

  # Finalizacja wymiany, atomowo pod pesymistycznym lockiem na Event: pod
  # lockiem re-walidujemy warunki, bo strony mogły się w międzyczasie ruszyć.
  #
  # Zwraca true przy sukcesie; false gdy warunki się zmieniły (kontroler
  # tłumaczy to na `swap_proposals.conditions_changed`). Gałęzie `next false`
  # nie potrzebują rollbacku — nic jeszcze nie zapisały.
  def accept!
    Event.transaction do
      event.lock!
      reload
      next false unless pending?

      proposer_p = event.participations.waitlist.find_by(user_id: proposer_id)
      target_p   = event.participations.confirmed.find_by(user_id: target_id)
      next false unless proposer_p && target_p

      expire_competing_proposals
      perform_swap!(proposer_p, target_p)
      true
    end
  end

  private

  # Wymiana zamyka też inne pending propozycje, które właśnie straciły sens:
  # pozostałe tego proposera (dostał już slot) i te celujące w tego targeta
  # (nie jest już confirmed).
  def expire_competing_proposals
    others = SwapProposal.pending.where(event_id: event_id).where.not(id: id)

    others.where(proposer_id: proposer_id).or(others.where(target_id: target_id)).update_all(status: SwapProposal.statuses[:expired])
  end

  # `swap_transition` wyłącza refill po stronie Participation — zwolniony slot
  # przejmuje proposer, a nie najstarszy waitlister.
  def perform_swap!(proposer_p, target_p)
    target_position = target_p.position

    update!(status: :accepted)

    target_p.swap_transition = :swapped_out
    target_p.update!(status: :cancelled)

    proposer_p.swap_transition = :swapped_in
    proposer_p.update!(status: :confirmed, position: target_position)

    Participation.resequence!(event, :waitlist)
  end

  def proposer_must_be_on_waitlist
    return if event.nil? || proposer_id.nil?
    return if event.participations.waitlist.exists?(user_id: proposer_id)

    errors.add(:base, "propozycję wymiany może złożyć tylko osoba z listy rezerwowej")
  end

  def target_must_be_confirmed
    return if event.nil? || target_id.nil?
    return if event.participations.confirmed.exists?(user_id: target_id)

    errors.add(:base, "wymianę można zaproponować tylko osobie z głównej listy")
  end

  def proposer_cannot_be_target
    return if proposer_id != target_id

    errors.add(:base, "nie możesz zaproponować wymiany samemu sobie")
  end
end
