require "application_system_test_case"

class EventsFilterToggleTest < ApplicationSystemTestCase
  test "filter pills switch the feed between upcoming and completed events" do
    upcoming = events(:gig_coordinators_tomorrow)
    done = Event.create!(
      host: hosts(:jan), name: "Zakończone wydarzenie",
      scheduled_at: 3.days.ago, ends_at: 3.days.ago + 2.hours,
      completed_at: 2.days.ago, pay_per_person: 100, capacity: 3
    )

    sign_in_as(users(:bartek))
    assert_current_path root_path, wait: 5

    # Default = Nadchodzące — only future events.
    assert_text upcoming.name
    assert_no_text done.name

    click_on "Wykonane"
    assert_current_path(/filter=completed/, wait: 5)
    assert_text done.name
    assert_no_text upcoming.name

    click_on "Nadchodzące"
    assert_current_path(/filter=new/, wait: 5)
    assert_text upcoming.name
    assert_no_text done.name
  end
end
