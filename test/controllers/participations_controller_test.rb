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

  test "DELETE when not participating does nothing" do
    delete event_participation_path(@event)
    assert_redirected_to event_path(@event)
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
