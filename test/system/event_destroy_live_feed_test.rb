require "application_system_test_case"

class EventDestroyLiveFeedTest < ApplicationSystemTestCase
  test "feed card is removed live when an event is destroyed" do
    event = events(:gig_coordinators_tomorrow)
    user  = users(:bartek)

    sign_in_as(user)
    assert_current_path root_path, wait: 5
    card_id = ActionView::RecordIdentifier.dom_id(event)
    assert_selector "##{card_id}"

    event.destroy!

    # Event#after_destroy_commit :broadcast_feed_remove fires a turbo-stream
    # remove on the :events channel.
    assert_no_selector "##{card_id}", wait: 5
  end
end
