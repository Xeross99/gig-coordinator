require "test_helper"

# Kontrakt „przeliczanie działa z konsoli": goły `update!(status: :cancelled)`
# na Participation / CampaignParticipation — bez kontrolera, bez serwisu —
# musi sam przeliczyć roster: promocja z waitlisty, refill po rezerwacji,
# kaskada kampania → sub-eventy, resequence pozycji i powiadomienia.
class CancellationConsoleContractTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @host = hosts(:jan)
    # Żaden user nie jest mistrzem — seed_reservations nie robi szumu,
    # a refill_one nie ma kogo zapraszać (testujemy czyste promocje).
    users(:ala).update!(title:      :kurnikowy_gangster)
    users(:bartek).update!(title:   :kurnikowy_gangster)
    users(:cezary).update!(title:   :kurzy_pacholek)
    users(:dominika).update!(title: :kurzy_pacholek)
  end

  # --- Kampania: confirmed → cancelled z konsoli ---

  test "console cancel of confirmed campaign participant promotes waitlister and cascades to sub-events" do
    campaign = EventCampaign.create!(host: @host, name: "Konsola", capacity: 2)
    sub = campaign.events.create!(
      name: "Sub 1", capacity: 2, pay_per_person: 100, host: @host,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )

    # enroll_in_sub_events buduje sub-roster z primary automatycznie.
    ala_cp    = campaign.campaign_participations.create!(user: users(:ala),    status: :confirmed, position: 1)
    campaign.campaign_participations.create!(user: users(:bartek), status: :confirmed, position: 2)
    cezary_cp = campaign.campaign_participations.create!(user: users(:cezary), status: :waitlist,  position: 1)

    assert sub.participations.confirmed.exists?(user_id: users(:ala).id), "setup: ala na sub-evencie"
    assert sub.participations.waitlist.exists?(user_id: users(:cezary).id), "setup: cezary na waitliście sub-eventu"

    # Dokładnie to, co admin wpisuje w `rails console`:
    ala_cp.update!(status: :cancelled)

    assert cezary_cp.reload.confirmed?, "cezary musi wskoczyć z rezerwy kampanii"
    assert_equal [ 1, 2 ], campaign.campaign_participations.confirmed.order(:position).pluck(:position)
    assert_equal [], campaign.campaign_participations.waitlist.pluck(:id)

    assert sub.participations.find_by(user_id: users(:ala).id).cancelled?,
           "ala musi wylecieć też z sub-eventu"
    assert sub.participations.confirmed.exists?(user_id: users(:cezary).id),
           "cezary (świeżo campaign-confirmed) musi dostać zwolniony slot sub-eventu"
    assert_equal [ 1, 2 ], sub.participations.confirmed.order(:position).pluck(:position)

    assert_enqueued_with(job: WebPushNotifier) # promocje poszły z powiadomieniami
  end

  test "console cancel of waitlisted campaign participant cascades and closes position gaps" do
    campaign = EventCampaign.create!(host: @host, name: "Konsola 2", capacity: 1)
    sub = campaign.events.create!(
      name: "Sub 1", capacity: 1, pay_per_person: 100, host: @host,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )

    campaign.campaign_participations.create!(user: users(:ala),    status: :confirmed, position: 1)
    bartek_cp = campaign.campaign_participations.create!(user: users(:bartek), status: :waitlist, position: 1)
    cezary_cp = campaign.campaign_participations.create!(user: users(:cezary), status: :waitlist, position: 2)

    bartek_cp.update!(status: :cancelled)

    assert cezary_cp.reload.waitlist?
    assert_equal [ 1 ], campaign.campaign_participations.waitlist.order(:position).pluck(:position)
    assert users(:ala).participations.find_by(event: sub).confirmed?, "confirmed nietknięty"
    assert sub.participations.find_by(user_id: users(:bartek).id).cancelled?,
           "waitlist sub-eventu też musi zostać wyczyszczona"
  end

  # --- Kampania: reserved → cancelled z konsoli (decline/expire semantyka) ---

  test "console cancel of reserved campaign participation refills the slot from the waitlist" do
    campaign = EventCampaign.create!(host: @host, name: "Konsola 3", capacity: 2)
    campaign.campaign_participations.create!(user: users(:ala), status: :confirmed, position: 1)
    reserved_cp = campaign.campaign_participations.create!(
      user: users(:bartek), status: :reserved, position: 2,
      reserved_until: 1.hour.from_now
    )
    cezary_cp = campaign.campaign_participations.create!(user: users(:cezary), status: :waitlist, position: 1)

    reserved_cp.update!(status: :cancelled, reserved_until: nil)

    assert cezary_cp.reload.confirmed?, "waitlist-first refill po odrzuconej rezerwacji"
    assert_equal [ 1, 2 ], campaign.campaign_participations.confirmed.order(:position).pluck(:position)
  end

  # --- Flat event: reserved → cancelled z konsoli ---

  test "console cancel of reserved flat participation refills the slot from the waitlist" do
    event = Event.create!(
      host: @host, name: "Flat", capacity: 2, pay_per_person: 100,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)
    reserved = Participation.create!(
      event: event, user: users(:bartek), status: :reserved, position: 2,
      reserved_until: 1.hour.from_now
    )
    waiting = Participation.create!(event: event, user: users(:cezary), status: :waitlist, position: 1)

    reserved.update!(status: :cancelled, reserved_until: nil)

    assert waiting.reload.confirmed?, "waitlist-first refill po odrzuconej rezerwacji"
    assert_equal [ 1, 2 ], event.participations.confirmed.order(:position).pluck(:position)
  end

  # --- Swap nie może triggerować refillu (slot przejmuje proposer) ---

  test "swap transition into cancelled does not trigger a refill" do
    event = Event.create!(
      host: @host, name: "Swap", capacity: 1, pay_per_person: 100,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )
    target   = Participation.create!(event: event, user: users(:ala),    status: :confirmed, position: 1)
    proposer = Participation.create!(event: event, user: users(:bartek), status: :waitlist,  position: 1)
    Participation.create!(event: event, user: users(:cezary), status: :waitlist, position: 2)

    Event.transaction do
      event.lock!
      target.swap_transition = :swapped_out
      target.update!(status: :cancelled)
      proposer.swap_transition = :swapped_in
      proposer.update!(status: :confirmed, position: 1)
      Participation.resequence!(event, :waitlist)
    end

    assert_equal [ users(:bartek).id ], event.participations.confirmed.pluck(:user_id),
                 "slot przejmuje proposer — nikt inny nie może zostać dopromowany"
    assert event.participations.waitlist.exists?(user_id: users(:cezary).id)
  end

  # --- Scheduling jobów wygaśnięcia (zamiast sweepera co minutę) ---

  test "creating a reservation schedules its own expiration job at reserved_until" do
    event = Event.create!(
      host: @host, name: "Joby", capacity: 2, pay_per_person: 100,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )
    deadline = 90.minutes.from_now
    reserved = Participation.create!(
      event: event, user: users(:ala), status: :reserved, position: 1,
      reserved_until: deadline
    )

    assert_enqueued_with(job: ReservationExpirationJob,
                         args: [ { participation_id: reserved.id } ],
                         at: deadline)
  end

  test "creating a campaign reservation schedules its own expiration job at reserved_until" do
    campaign = EventCampaign.create!(host: @host, name: "Jobki", capacity: 2)
    deadline = 90.minutes.from_now
    reserved = campaign.campaign_participations.create!(
      user: users(:ala), status: :reserved, position: 1, reserved_until: deadline
    )

    assert_enqueued_with(job: ReservationExpirationJob,
                         args: [ { campaign_participation_id: reserved.id } ],
                         at: deadline)
  end

  test "per-id expiration job is idempotent — accepted reservation stays confirmed" do
    event = Event.create!(
      host: @host, name: "Idempotent", capacity: 2, pay_per_person: 100,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )
    reserved = Participation.create!(
      event: event, user: users(:ala), status: :reserved, position: 1,
      reserved_until: 1.minute.ago
    )
    reserved.update!(status: :confirmed, reserved_until: nil)

    ReservationExpirationJob.perform_now(participation_id: reserved.id)

    assert reserved.reload.confirmed?, "zaakceptowana rezerwacja nie może zostać wygaszona"
  end

  test "per-id expiration job cancels an overdue reservation and the slot gets refilled" do
    event = Event.create!(
      host: @host, name: "Wygasanie", capacity: 1, pay_per_person: 100,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )
    reserved = Participation.create!(
      event: event, user: users(:ala), status: :reserved, position: 1,
      reserved_until: 1.hour.from_now
    )
    waiting = Participation.create!(event: event, user: users(:bartek), status: :waitlist, position: 1)
    reserved.update_column(:reserved_until, 2.minutes.ago)

    ReservationExpirationJob.perform_now(participation_id: reserved.id)

    assert reserved.reload.cancelled?
    assert_equal "expired", reserved.participation_events.order(:id).last.event_type,
                 "historia musi rozróżnić wygaśnięcie od decline"
    assert waiting.reload.confirmed?, "zwolniony slot idzie do waitlisty"
  end

  test "creating a swap proposal schedules SwapExpirationJob at expires_at" do
    event = Event.create!(
      host: @host, name: "SwapJob", capacity: 1, pay_per_person: 100,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours
    )
    Participation.create!(event: event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek), status: :waitlist,  position: 1)
    deadline = SwapProposal::EXPIRATION_WINDOW.from_now
    proposal = SwapProposal.create!(event: event, proposer: users(:bartek), target: users(:ala),
                                    expires_at: deadline)

    assert_enqueued_with(job: SwapExpirationJob,
                         args: [ { swap_proposal_id: proposal.id } ],
                         at: deadline)

    proposal.update_column(:expires_at, 5.minutes.ago)
    SwapExpirationJob.perform_now(swap_proposal_id: proposal.id)
    assert proposal.reload.expired?
  end
end
