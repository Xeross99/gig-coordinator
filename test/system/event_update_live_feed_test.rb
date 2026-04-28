require "application_system_test_case"

class EventUpdateLiveFeedTest < ApplicationSystemTestCase
  test "feed card replaces live when an event is renamed" do
    event = events(:gig_coordinators_tomorrow)
    user  = users(:bartek)

    sign_in_as(user)
    assert_current_path root_path, wait: 5
    assert_text event.name

    original_name = event.name
    new_name = "Zupełnie nowa nazwa"
    event.update!(name: new_name)

    # Event#after_update_commit :broadcast_feed_replace replaces the card on the
    # :events stream — no refresh needed on the worker's side.
    assert_text new_name, wait: 5
    assert_no_text original_name
  end
end
