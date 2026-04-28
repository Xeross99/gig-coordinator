require "application_system_test_case"

class NewEventLiveFeedTest < ApplicationSystemTestCase
  test "user is pulled to the newly created event page via Turbo Stream visit action" do
    host = hosts(:jan)
    user = users(:ala)

    sign_in_as(user)
    assert_current_path root_path
    assert_text events(:gig_coordinators_tomorrow).name

    event = host.events.create!(
      name: "Wiosenne sprzątanie",
      scheduled_at: 1.day.from_now,
      ends_at: 1.day.from_now + 4.hours,
      pay_per_person: 100,
      capacity: 3
    )

    # Event#broadcast_visit_to_feed sends a `visit` Turbo::StreamAction that
    # navigates the browser to the new event page. No manual click needed.
    assert_current_path event_path(event), wait: 5
    assert_text "Wiosenne sprzątanie"
  end
end
