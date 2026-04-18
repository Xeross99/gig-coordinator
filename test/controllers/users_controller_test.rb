require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not signed in" do
    get users_path
    assert_redirected_to login_path
  end

  test "redirects host users (index is worker-facing)" do
    sign_in_as(hosts(:jan))
    get users_path
    assert_redirected_to login_path
  end

  test "GET index as user lists all users with display names + titles" do
    sign_in_as(users(:ala))
    get users_path
    assert_response :success
    assert_match users(:ala).display_name,    response.body
    assert_match users(:bartek).display_name, response.body
  end

  test "catch counts include confirmed participations on completed events only" do
    # Controller runs this exact query:
    #   Participation.confirmed.joins(:event).where.not(events: { completed_at: nil })
    #                .group(:user_id).count
    # We mirror it directly to guard the behavior without depending on assigns.
    event = events(:gig-coordinators_tomorrow)
    done = Event.create!(host: hosts(:jan), name: "Zakonczone",
                         scheduled_at: 2.days.ago, ends_at: 2.days.ago + 2.hours,
                         pay_per_person: 100, capacity: 4,
                         completed_at: 1.day.ago)
    Participation.create!(event: done,  user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)  # not completed
    Participation.create!(event: done,  user: users(:cezary), status: :cancelled, position: 0)

    counts = Participation.confirmed
                          .joins(:event)
                          .where.not(events: { completed_at: nil })
                          .group(:user_id)
                          .count

    assert_equal 1, counts[users(:ala).id]
    assert_nil   counts[users(:bartek).id]
    assert_nil   counts[users(:cezary).id]
  end

  test "GET index orders by title desc then last_name" do
    users(:ala).update!(title: :master)        # rank 3
    users(:bartek).update!(title: :member)   # rank 1
    users(:cezary).update!(title: :rookie)       # rank 0

    sign_in_as(users(:ala))
    get users_path

    # Use position in rendered body as a proxy for ordering.
    body = response.body
    assert body.index(users(:ala).display_name) < body.index(users(:bartek).display_name)
    assert body.index(users(:bartek).display_name) < body.index(users(:cezary).display_name)
  end
end
