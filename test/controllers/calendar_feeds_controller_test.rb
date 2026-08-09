require "test_helper"

class CalendarFeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:ala)
    @user.update_column(:calendar_token, "a" * 40)
    @host = hosts(:jan)
  end

  test "GET feed zwraca .ics z confirmed eventami usera" do
    event = Event.create!(host: @host, name: "Łapanie kur",
                          scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
                          capacity: 4, pay_per_person: 100)
    Participation.create!(event: event, user: @user, status: :confirmed, position: 1)

    get calendar_feed_path(token: @user.calendar_token)

    assert_response :success
    assert_match %r{text/calendar}, response.media_type
    assert_match "BEGIN:VCALENDAR", response.body
    assert_match "Łapanie kur", response.body
    assert_match "BEGIN:VEVENT", response.body
  end

  test "GET feed nie pokazuje cancelled / waitlist" do
    cancelled = Event.create!(host: @host, name: "Anulowane łapanie",
                              scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
                              capacity: 4, pay_per_person: 100)
    Participation.create!(event: cancelled, user: @user, status: :cancelled, position: 1)

    waitlist = Event.create!(host: @host, name: "Rezerwowe łapanie",
                             scheduled_at: 3.days.from_now, ends_at: 3.days.from_now + 2.hours,
                             capacity: 4, pay_per_person: 100)
    Participation.create!(event: waitlist, user: @user, status: :waitlist, position: 1)

    get calendar_feed_path(token: @user.calendar_token)

    refute_match "Anulowane łapanie", response.body
    refute_match "Rezerwowe łapanie", response.body
  end

  test "GET feed nie pokazuje eventów innych userów" do
    other_user = users(:bartek)
    event = Event.create!(host: @host, name: "Cudze łapanie",
                          scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
                          capacity: 4, pay_per_person: 100)
    Participation.create!(event: event, user: other_user, status: :confirmed, position: 1)

    get calendar_feed_path(token: @user.calendar_token)

    refute_match "Cudze łapanie", response.body
  end

  test "GET feed z nieznanym tokenem zwraca 404" do
    get calendar_feed_path(token: "f" * 40)
    assert_response :not_found
  end

  test "feed nie wymaga sesji (Apple Calendar nie wysyła cookies)" do
    cookies.delete(:session_token)
    get calendar_feed_path(token: @user.calendar_token)
    assert_response :success
  end
end
