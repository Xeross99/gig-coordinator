require "test_helper"

class ParticipationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:gig-coordinators_tomorrow) # capacity: 4
    sign_in_as(users(:ala))
  end

  test "POST requires login" do
    delete session_path
    post event_participation_path(@event)
    assert_redirected_to login_path
  end

  test "POST create with spots available creates confirmed participation" do
    assert_difference "Participation.confirmed.count", 1 do
      post event_participation_path(@event)
    end
    p = Participation.order(:id).last
    assert p.confirmed?
    assert_equal 1, p.position
    assert_redirected_to event_path(@event)
  end

  test "POST create when event is full creates waitlist participation" do
    4.times.with_index do |i|
      Participation.create!(event: @event, user: User.create!(first_name: "X", last_name: "Y#{i}", email: "x#{i}@example.com"),
                            status: :confirmed, position: i + 1)
    end
    assert_difference "Participation.waitlist.count", 1 do
      post event_participation_path(@event)
    end
    p = Participation.order(:id).last
    assert p.waitlist?
    assert_equal 1, p.position
  end

  test "POST create refuses duplicate for same user" do
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    assert_redirected_to event_path(@event)
  end

  test "DELETE destroys own confirmed participation (marks cancelled)" do
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    delete event_participation_path(@event)
    p = Participation.find_by(event: @event, user: users(:ala))
    assert p.cancelled?
    assert_redirected_to event_path(@event)
  end

  test "POST create after cancel re-activates the existing participation" do
    Participation.create!(event: @event, user: users(:ala), status: :cancelled, position: 0)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    p = Participation.find_by(event: @event, user: users(:ala))
    assert p.confirmed?, "expected re-join to land as confirmed when capacity available"
  end

  test "cancelling a confirmed spot and re-joining lands at the END of the waitlist when event is full" do
    @event.update!(capacity: 2)

    # Start: ala + bartek confirmed (fill capacity), cezary + dominika on waitlist.
    Participation.create!(event: @event, user: users(:ala),      status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek),   status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:cezary),   status: :waitlist,  position: 1)
    Participation.create!(event: @event, user: users(:dominika), status: :waitlist,  position: 2)

    # Ala cancels → cezary gets promoted to confirmed; dominika still waitlist #2.
    delete event_participation_path(@event)
    assert users(:cezary).participations.find_by(event: @event).confirmed?,
           "expected cezary to be promoted after ala cancels"
    assert users(:dominika).participations.find_by(event: @event).waitlist?,
           "expected dominika to stay on waitlist"

    # Ala re-joins. Event is full (bartek + cezary). She must land at the END of the
    # waitlist (after dominika), not skip ahead of people who were already waiting.
    post event_participation_path(@event)

    ala_p = users(:ala).participations.find_by(event: @event)
    assert ala_p.waitlist?, "expected ala to land on waitlist when event is full"
    assert_operator ala_p.position, :>, users(:dominika).participations.find_by(event: @event).position,
                    "expected ala to land after dominika (end of waitlist)"

    waitlist_order = @event.participations.waitlist.order(:position).map(&:user)
    assert_equal [ users(:dominika), users(:ala) ], waitlist_order,
                 "waitlist order should be [dominika, ala] — earlier waiters keep their spot"
  end

  test "DELETE when not participating does nothing" do
    delete event_participation_path(@event)
    assert_redirected_to event_path(@event)
  end

  test "clicking Akceptuję on a stale page ends up on the waitlist when event filled up in the meantime" do
    @event.update!(capacity: 1)

    # Ala loads the event page — only 0/1 taken, button shows "Akceptuję".
    get event_path(@event)
    assert_response :success
    assert_match I18n.t("events.accept"), response.body
    assert_no_match I18n.t("events.waitlist_accept"), response.body

    # Bartek grabs the last seat before Ala clicks.
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)

    # Ala clicks what was "Akceptuję" — lock re-evaluates capacity, she lands on waitlist.
    assert_difference "@event.participations.waitlist.count", 1 do
      post event_participation_path(@event)
    end
    ala_participation = @event.participations.find_by(user: users(:ala))
    assert ala_participation.waitlist?, "expected Ala to land on waitlist when event filled up"

    # After redirect Ala sees the waitlist badge + cancel button, not the waitlist-accept CTA.
    follow_redirect!
    assert_match I18n.t("events.waitlist_badge"), response.body
    assert_match I18n.t("events.cancel"), response.body
    assert_no_match I18n.t("events.waitlist_accept"), response.body
  end

  test "concurrent creates do not exceed capacity" do
    users_list = 6.times.map do |i|
      User.create!(first_name: "Race#{i}", last_name: "User", email: "race#{i}@example.com")
    end

    # Serialize via the same lock the controller uses — test semantic correctness (not race)
    users_list.each do |u|
      get verify_magic_link_path(token: u.signed_id(purpose: :magic_link, expires_in: 15.minutes))
      post event_participation_path(@event)
    end

    assert_equal @event.capacity, @event.participations.confirmed.count
    assert_equal 2, @event.participations.waitlist.count
  end
end
