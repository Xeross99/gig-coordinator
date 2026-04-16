require "application_system_test_case"

class NewEventLiveFeedTest < ApplicationSystemTestCase
  test "user sees newly created event appear in feed without refresh" do
    host = hosts(:jan)
    user = users(:ala)

    visit verify_magic_link_url(token: user.signed_id(purpose: :magic_link, expires_in: 15.minutes))
    assert_current_path root_path
    assert_text events(:gig-coordinators_tomorrow).name
    assert_no_text "Wiosenne sprzątanie"

    # Host creates an event in a separate Rails context (simulates host server-side action)
    host.events.create!(
      name: "Wiosenne sprzątanie",
      scheduled_at: 1.day.from_now,
      ends_at: 1.day.from_now + 4.hours,
      pay_per_person: 100,
      capacity: 3
    )

    # User's feed updates live via Turbo Stream — no refresh
    within "#events_list" do
      assert_text "Wiosenne sprzątanie", wait: 5
    end
  end
end
