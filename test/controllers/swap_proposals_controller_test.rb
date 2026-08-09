require "test_helper"

class SwapProposalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:chickens_tomorrow) # capacity: 4
    @event.participations.destroy_all
    @event.swap_proposals.destroy_all
  end

  # --- CREATE ---

  test "POST create — waitlist user proposes swap to confirmed user" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sign_in_as(users(:ala))

    assert_difference "SwapProposal.count", 1 do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end

    sp = SwapProposal.last
    assert sp.pending?
    assert_equal users(:ala).id, sp.proposer_id
    assert_equal users(:bartek).id, sp.target_id
    assert sp.expires_at > Time.current
    assert_redirected_to event_path(@event)
    assert_equal "Propozycja wymiany wysłana.", flash[:notice]
  end

  test "POST create — confirmed user cannot propose (not on waitlist)" do
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)

    sign_in_as(users(:ala))

    assert_no_difference "SwapProposal.count" do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end

    assert_redirected_to event_path(@event)
    assert_equal "Tylko osoby z listy rezerwowej mogą proponować wymianę.", flash[:alert]
  end

  test "POST create — cannot propose to non-confirmed user" do
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :waitlist, position: 2)

    sign_in_as(users(:ala))

    assert_no_difference "SwapProposal.count" do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end

    assert_redirected_to event_path(@event)
    assert_equal "Można proponować wymianę tylko potwierdzonej osobie.", flash[:alert]
  end

  test "POST create — blocked user cannot propose" do
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    HostBlock.create!(user: users(:ala), host: @event.host)

    sign_in_as(users(:ala))

    assert_no_difference "SwapProposal.count" do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end

    assert_redirected_to event_path(@event)
    assert_equal Copy::Participations::BLOCKED, flash[:alert]
  end

  test "POST create — duplicate pending proposal rejected" do
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                         expires_at: 1.hour.from_now)

    sign_in_as(users(:ala))

    assert_no_difference "SwapProposal.count" do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end

    assert_redirected_to event_path(@event)
    assert_equal "Masz już oczekującą propozycję wymiany dla tej osoby.", flash[:alert]
  end

  test "POST create — event lock blocks swap on started event" do
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)

    sign_in_as(users(:ala))

    assert_no_difference "SwapProposal.count" do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end

    assert_redirected_to event_path(@event)
    assert_equal "Zlecenie już się rozpoczęło - zmiany niemożliwe.", flash[:alert]
  end

  test "POST create — requires login" do
    post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    assert_redirected_to login_path
  end

  # --- ACCEPT ---

  test "POST accept — proposer becomes confirmed at target's position, target cancelled" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    sp.reload
    assert sp.accepted?

    ala_p = @event.participations.find_by(user: users(:ala))
    assert ala_p.confirmed?
    assert_equal 1, ala_p.position

    bartek_p = @event.participations.find_by(user: users(:bartek))
    assert bartek_p.cancelled?

    assert_redirected_to event_path(@event)
    assert_equal "Wymiana zaakceptowana!", flash[:notice]
  end

  test "POST accept — other users' positions are NOT affected by swap" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:dominika), status: :confirmed, position: 3)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    cezary_p = @event.participations.find_by(user: users(:cezary))
    assert cezary_p.confirmed?
    assert_equal 2, cezary_p.position

    dominika_p = @event.participations.find_by(user: users(:dominika))
    assert dominika_p.confirmed?
    assert_equal 3, dominika_p.position
  end

  test "POST accept — waitlist resequenced after proposer leaves it" do
    @event.update!(capacity: 2)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    Participation.create!(event: @event, user: users(:dominika), status: :waitlist, position: 2)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    dominika_p = @event.participations.find_by(user: users(:dominika))
    assert dominika_p.waitlist?
    assert_equal 1, dominika_p.position, "waitlist should be resequenced — dominika becomes position 1"
  end

  test "POST accept — non-target user cannot accept" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:cezary))
    post accept_event_swap_proposal_path(@event, sp)

    assert_redirected_to event_path(@event)
    assert_equal Copy::SwapProposals::NOT_YOUR_PROPOSAL, flash[:alert]
    assert sp.reload.pending?
  end

  test "POST accept — expired proposal cannot be accepted" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)
    sp.update_column(:expires_at, 5.minutes.ago)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    assert_redirected_to event_path(@event)
    assert_equal "Propozycja wymiany wygasła.", flash[:alert]
    assert sp.reload.expired?
  end

  test "POST accept — race condition: proposer no longer on waitlist" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    # Ala gets promoted before bartek accepts
    @event.participations.find_by(user: users(:ala)).update!(status: :confirmed, position: 2)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    assert_redirected_to event_path(@event)
    assert_equal Copy::SwapProposals::CONDITIONS_CHANGED, flash[:alert]
    bartek_p = @event.participations.find_by(user: users(:bartek))
    assert bartek_p.confirmed?, "target should remain confirmed when conditions changed"
  end

  test "POST accept — race condition: target no longer confirmed" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    # Bartek cancels before he can accept (some other code path)
    @event.participations.find_by(user: users(:bartek)).update!(status: :cancelled)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    assert_redirected_to event_path(@event)
    assert_equal Copy::SwapProposals::CONDITIONS_CHANGED, flash[:alert]
  end

  test "POST accept — cancels other pending proposals for same proposer" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp1 = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                               expires_at: 1.hour.from_now)
    sp2 = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:cezary),
                               expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp1)

    assert sp1.reload.accepted?
    assert sp2.reload.expired?, "other proposals by the same proposer should be expired"
  end

  test "POST accept — cancels other pending proposals targeting the same target" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    Participation.create!(event: @event, user: users(:dominika), status: :waitlist, position: 2)

    sp1 = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                               expires_at: 1.hour.from_now)
    sp2 = SwapProposal.create!(event: @event, proposer: users(:dominika), target: users(:bartek),
                               expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp1)

    assert sp1.reload.accepted?
    assert sp2.reload.expired?, "other proposals targeting the cancelled target should be expired"
  end

  test "POST accept — event lock blocks swap on started event" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    assert_redirected_to event_path(@event)
    assert_equal "Zlecenie już się rozpoczęło - zmiany niemożliwe.", flash[:alert]
    assert sp.reload.pending?
  end

  test "POST accept — audit log records swapped_in and swapped_out" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    ala_events = @event.participations.find_by(user: users(:ala))
                       .participation_events.order(:id)
    bartek_events = @event.participations.find_by(user: users(:bartek))
                          .participation_events.order(:id)

    assert ala_events.any? { |e| e.swapped_in? }, "proposer should have swapped_in audit entry"
    assert bartek_events.any? { |e| e.swapped_out? }, "target should have swapped_out audit entry"
  end

  # --- DECLINE ---

  test "POST decline — target declines proposal" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post decline_event_swap_proposal_path(@event, sp)

    assert sp.reload.declined?
    assert_redirected_to event_path(@event)
    assert_equal "Propozycja odrzucona.", flash[:notice]

    bartek_p = @event.participations.find_by(user: users(:bartek))
    assert bartek_p.confirmed?, "target should remain confirmed after declining"

    ala_p = @event.participations.find_by(user: users(:ala))
    assert ala_p.waitlist?, "proposer should remain on waitlist after decline"
  end

  test "POST decline — non-target user cannot decline" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:cezary))
    post decline_event_swap_proposal_path(@event, sp)

    assert_redirected_to event_path(@event)
    assert_equal Copy::SwapProposals::NOT_YOUR_PROPOSAL, flash[:alert]
    assert sp.reload.pending?
  end

  # --- AUTO-EXPIRATION ---

  test "waitlist promotion auto-expires proposer's pending swap proposals" do
    @event.update!(capacity: 2)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:cezary),
                              expires_at: 1.hour.from_now)

    # Bartek cancels → ala gets promoted from waitlist
    sign_in_as(users(:bartek))
    delete event_participation_path(@event)

    ala_p = @event.participations.find_by(user: users(:ala))
    assert ala_p.confirmed?, "ala should be promoted"

    assert sp.reload.expired?, "swap proposal should be auto-expired after proposer got promoted"
  end

  test "cancellation auto-expires all proposals involving the cancelled user" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    Participation.create!(event: @event, user: users(:dominika), status: :waitlist, position: 2)

    sp_ala = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                                  expires_at: 1.hour.from_now)
    sp_dominika = SwapProposal.create!(event: @event, proposer: users(:dominika), target: users(:bartek),
                                       expires_at: 1.hour.from_now)

    # Bartek cancels — all proposals targeting him should expire
    sign_in_as(users(:bartek))
    delete event_participation_path(@event)

    assert sp_ala.reload.expired?, "proposals targeting cancelled user should expire"
    assert sp_dominika.reload.expired?, "proposals targeting cancelled user should expire"
  end

  # --- PROPOSE AGAIN AFTER DECLINE ---

  test "POST create — can propose again to the same target after previous proposal was declined" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)
    sp.update!(status: :declined)

    sign_in_as(users(:ala))

    assert_difference "SwapProposal.count", 1 do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end

    new_sp = SwapProposal.pending.last
    assert_equal users(:ala).id, new_sp.proposer_id
    assert_equal users(:bartek).id, new_sp.target_id
  end

  test "POST create — can propose to multiple confirmed users simultaneously" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sign_in_as(users(:ala))

    assert_difference "SwapProposal.count", 2 do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
      post event_swap_proposals_path(@event), params: { target_user_id: users(:cezary).id }
    end

    assert SwapProposal.pending.exists?(event: @event, proposer: users(:ala), target: users(:bartek))
    assert SwapProposal.pending.exists?(event: @event, proposer: users(:ala), target: users(:cezary))
  end

  # --- CAPACITY INVARIANT ---

  test "POST accept — confirmed count stays the same (swap does not exceed capacity)" do
    @event.update!(capacity: 3)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:dominika), status: :confirmed, position: 3)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    confirmed_before = @event.participations.confirmed.count

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(@event, sp)

    assert_equal confirmed_before, @event.participations.reload.confirmed.count,
                 "swap should not change total confirmed count"
    assert @event.participations.confirmed.count <= @event.capacity,
           "confirmed must not exceed capacity"
  end

  # --- CARPOOL CLEANUP ---

  test "POST accept — carpool offer of cancelled target is destroyed" do
    # ala has can_drive: true in fixtures
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :waitlist, position: 1)
    CarpoolOffer.create!(event: @event, user: users(:ala))

    sp = SwapProposal.create!(event: @event, proposer: users(:bartek), target: users(:ala),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:ala))

    assert_difference "CarpoolOffer.count", -1 do
      post accept_event_swap_proposal_path(@event, sp)
    end

    assert_equal 0, CarpoolOffer.where(event: @event, user: users(:ala)).count
  end

  # --- PUSH NOTIFICATIONS ---

  test "POST create enqueues swap_proposal push notification" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sign_in_as(users(:ala))

    assert_enqueued_with(job: WebPushNotifier) do
      post event_swap_proposals_path(@event), params: { target_user_id: users(:bartek).id }
    end
  end

  test "POST accept enqueues swap_accepted push notification" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))

    assert_enqueued_with(job: WebPushNotifier) do
      post accept_event_swap_proposal_path(@event, sp)
    end
  end

  test "POST decline enqueues swap_declined push notification" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))

    assert_enqueued_with(job: WebPushNotifier) do
      post decline_event_swap_proposal_path(@event, sp)
    end
  end

  # --- DECLINE EVENT LOCK ---

  test "POST decline blocked once event has started" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                              expires_at: 1.hour.from_now)

    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post decline_event_swap_proposal_path(@event, sp)

    assert_redirected_to event_path(@event)
    assert_equal "Zlecenie już się rozpoczęło - zmiany niemożliwe.", flash[:alert]
    assert sp.reload.pending?, "proposal should remain pending when event is locked"
  end

  # --- VIEW TESTS ---

  test "GET event show — roster shows Zamien button for waitlist user next to confirmed users" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_select "form[action=?]", event_swap_proposals_path(@event), minimum: 1
    assert_match Copy::SwapProposals::PROPOSE_SHORT, response.body
  end

  test "GET event show — roster shows disabled Wymiana label (not a form) for confirmed user" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 2)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_match "Wymiana", response.body
    assert_select "form[action=?]", event_swap_proposals_path(@event), count: 0
  end

  test "GET event show — roster shows Oczekuje label when proposal already sent" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                         expires_at: 1.hour.from_now)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_match "Oczekuje", response.body
  end

  test "GET event show — participation button shows swap banner for confirmed target with pending proposal" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                         expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    get event_path(@event)

    assert_response :success
    assert_match "chce się z Tobą zamienić", response.body
    assert_match "Akceptuj wymianę", response.body
    assert_match "Odrzuć", response.body
  end

  test "GET event show — participation button shows waiting status for waitlist proposer" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                         expires_at: 1.hour.from_now)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_match "Propozycja wymiany wysłana", response.body
    assert_match "Czekasz na odpowiedź od:", response.body
  end

  test "GET event show — roster does NOT show Wymiana label next to yourself" do
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_no_match "Wymiana", response.body
  end

  test "GET event show — roster does NOT show Wymiana on started event" do
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_no_match "Wymiana", response.body
  end

  test "GET event show — roster shows disabled Wymiana for user with no participation" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_match "Wymiana", response.body
    assert_select "form[action=?]", event_swap_proposals_path(@event), count: 0
  end

  test "GET event show — roster shows disabled Wymiana tooltip for non-waitlist user" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 2)

    sign_in_as(users(:ala))
    get event_path(@event)

    assert_response :success
    assert_select "span[title=?]", "Zapisz się na rezerwę, aby zaproponować wymianę"
  end

  # --- SWEEPER ---

  test "ReservationExpirationJob expires stale swap proposals" do
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)

    stale_sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:bartek),
                                    expires_at: 1.hour.from_now)
    stale_sp.update_column(:expires_at, 5.minutes.ago)

    fresh_sp = SwapProposal.create!(event: @event, proposer: users(:ala), target: users(:cezary),
                                    expires_at: 1.hour.from_now)

    ReservationExpirationJob.perform_now

    assert stale_sp.reload.expired?, "stale proposal should be expired by sweeper"
    assert fresh_sp.reload.pending?, "fresh proposal should remain pending"
  end

  # --- MODEL: classify_transition ---

  test "classify_transition returns swapped_in when swap_transition is set" do
    p = Participation.create!(event: @event, user: users(:ala), status: :waitlist, position: 1)
    p.swap_transition = :swapped_in
    p.update!(status: :confirmed, position: 1)

    audit = p.participation_events.order(:id).last
    assert_equal "swapped_in", audit.event_type
  end

  test "classify_transition returns swapped_out when swap_transition is set" do
    p = Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    p.swap_transition = :swapped_out
    p.update!(status: :cancelled)

    audit = p.participation_events.order(:id).last
    assert_equal "swapped_out", audit.event_type
  end

  # --- SUB-EVENTY KAMPANII (rzutów) ---
  # Wymiana działa per pojedyncze łapanie w rzucie — jak "Wypisz mnie z tego
  # łapania", nie dotyka primary rosteru kampanii.

  test "GET sub-event show — confirmed target widzi banner wymiany z Akceptuję/Odrzuć" do
    sub = build_sub_event
    Participation.create!(event: sub, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: sub, user: users(:ala), status: :waitlist, position: 1)
    SwapProposal.create!(event: sub, proposer: users(:ala), target: users(:bartek),
                         expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    get event_path(sub)

    assert_response :success
    assert_match "chce się z Tobą zamienić", response.body
    assert_match "Akceptuj wymianę", response.body
    assert_match "Odrzuć", response.body
  end

  test "GET sub-event show — waitlist proposer widzi status oczekiwania" do
    sub = build_sub_event
    Participation.create!(event: sub, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: sub, user: users(:ala), status: :waitlist, position: 1)
    SwapProposal.create!(event: sub, proposer: users(:ala), target: users(:bartek),
                         expires_at: 1.hour.from_now)

    sign_in_as(users(:ala))
    get event_path(sub)

    assert_response :success
    assert_match "Propozycja wymiany wysłana", response.body
    assert_match "Czekasz na odpowiedź od:", response.body
  end

  test "POST accept na sub-evencie — swap zamienia miejsca, primary roster kampanii nietknięty" do
    sub = build_sub_event
    campaign = sub.event_campaign

    # Realny setup: zapisy przez rzut — bartek łapie slot (cap=1), ala idzie na waitlistę sub-eventu
    CampaignParticipation.create!(event_campaign: campaign, user: users(:bartek), status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: campaign, user: users(:ala), status: :confirmed, position: 2)

    bartek_p = sub.participations.find_by(user: users(:bartek))
    ala_p    = sub.participations.find_by(user: users(:ala))
    assert bartek_p.confirmed?
    assert ala_p.waitlist?

    proposal = SwapProposal.create!(event: sub, proposer: users(:ala), target: users(:bartek),
                                    expires_at: 1.hour.from_now)

    sign_in_as(users(:bartek))
    post accept_event_swap_proposal_path(sub, proposal)

    assert_redirected_to event_path(sub)
    assert proposal.reload.accepted?
    assert bartek_p.reload.cancelled?
    assert ala_p.reload.confirmed?
    assert_equal 1, ala_p.position

    # Primary roster rzutu bez zmian — wymiana dotyczy tylko tego jednego łapania
    assert campaign.campaign_participations.find_by(user: users(:bartek)).confirmed?
    assert campaign.campaign_participations.find_by(user: users(:ala)).confirmed?
  end

  private

  def build_sub_event
    campaign = EventCampaign.create!(name: "Rzut testowy", host: @event.host, capacity: 4)
    campaign.campaign_participations.destroy_all # wyczyść auto-seedowane rezerwacje mistrzów
    sub = Event.create!(name: "Łapanie w rzucie", host: @event.host, event_campaign: campaign,
                        scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
                        capacity: 1, pay_per_person: 100)
    sub.participations.destroy_all
    sub
  end
end
