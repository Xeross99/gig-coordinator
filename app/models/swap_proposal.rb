class SwapProposal < ApplicationRecord
  EXPIRATION_WINDOW = 1.hour

  belongs_to :event
  belongs_to :proposer, class_name: "User"
  belongs_to :target, class_name: "User"

  enum :status, { pending: 0, accepted: 1, declined: 2, expired: 3 }

  validates :proposer_id, uniqueness: {
    scope: %i[event_id target_id],
    conditions: -> { where(status: :pending) },
    message: "already has a pending proposal for this target"
  }

  validate :proposer_must_be_on_waitlist, on: :create
  validate :target_must_be_confirmed, on: :create
  validate :proposer_cannot_be_target

  # Jeden job wygaśnięcia per propozycja, odpalany dokładnie o expires_at —
  # zamiast sweepera co minutę. Idempotentny (job sprawdza pending? + czas).
  after_create_commit :schedule_expiration_job

  def time_expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Finalizacja wymiany — atomowo pod pesymistycznym lockiem na Event
  # (jedna implementacja dla web SwapProposalsController i API).
  # Pod lockiem re-walidujemy warunki (pending? + strony wciąż na swoich
  # pozycjach), unieważniamy konkurencyjne pending propozycje (pozostałe
  # tego proposera i te celujące w tego targeta na tym evencie), robimy
  # swap pozycji (`swap_transition` wyłącza refill — slot przejmuje
  # proposer, nie waitlista) i resequence waitlisty.
  #
  # Zwraca true przy sukcesie; false gdy warunki się zmieniły (kontrolery
  # tłumaczą to na `swap_proposals.conditions_changed`).
  def accept!
    error = false

    Event.transaction do
      event.lock!
      reload

      unless pending?
        error = true
        raise ActiveRecord::Rollback
      end

      proposer_p = event.participations.waitlist.find_by(user_id: proposer_id)
      target_p   = event.participations.confirmed.find_by(user_id: target_id)

      unless proposer_p && target_p
        error = true
        raise ActiveRecord::Rollback
      end

      target_position = target_p.position

      SwapProposal.pending.where(event: event, proposer_id: proposer_id)
                  .where.not(id: id)
                  .update_all(status: SwapProposal.statuses[:expired])

      SwapProposal.pending.where(event: event, target_id: target_id)
                  .where.not(id: id)
                  .update_all(status: SwapProposal.statuses[:expired])

      update!(status: :accepted)

      target_p.swap_transition = :swapped_out
      target_p.update!(status: :cancelled)

      proposer_p.swap_transition = :swapped_in
      proposer_p.update!(status: :confirmed, position: target_position)

      Participation.resequence!(event, :waitlist)
    end

    !error
  end

  private

  def schedule_expiration_job
    return if expires_at.blank?

    SwapExpirationJob.set(wait_until: expires_at).perform_later(swap_proposal_id: id)
  end

  def proposer_must_be_on_waitlist
    return if event.nil? || proposer_id.nil?
    unless event.participations.waitlist.exists?(user_id: proposer_id)
      errors.add(:proposer, "must be on the waitlist")
    end
  end

  def target_must_be_confirmed
    return if event.nil? || target_id.nil?
    unless event.participations.confirmed.exists?(user_id: target_id)
      errors.add(:target, "must be confirmed")
    end
  end

  def proposer_cannot_be_target
    errors.add(:target, "cannot be the same as proposer") if proposer_id == target_id
  end
end
