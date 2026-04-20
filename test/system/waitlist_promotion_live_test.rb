require "application_system_test_case"

class WaitlistPromotionLiveTest < ApplicationSystemTestCase
  test "waitlisted user's roster flips live when a confirmed attendee cancels" do
    host     = hosts(:jan)
    first    = users(:bartek)    # confirmed, will cancel
    second   = users(:cezary)    # confirmed, stays put
    promoted = users(:dominika)  # waitlist → should be promoted

    event = host.events.create!(
      name: "Promocja z listy rezerwowej",
      scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
      pay_per_person: 100, capacity: 2
    )
    # seed_on_create auto-reserved top-tier users; wipe them so we can set up an
    # explicit confirmed/waitlist scenario.
    event.participations.destroy_all
    Participation.create!(event: event, user: first,    status: :confirmed, position: 1)
    Participation.create!(event: event, user: second,   status: :confirmed, position: 2)
    Participation.create!(event: event, user: promoted, status: :waitlist,  position: 1)

    roster_id = ActionView::RecordIdentifier.dom_id(event, :roster)

    using_session("promoted_user") do
      sign_in_as(promoted)
      click_on event.name
      assert_current_path event_path(event), wait: 5
      assert_text I18n.t("events.waitlist_badge")
      within "##{roster_id}" do
        # Header is styled `uppercase` via Tailwind, so Capybara sees "REZERWA".
        assert_text "REZERWA (1)"
      end
    end

    using_session("canceller") do
      sign_in_as(first)
      click_on event.name
      assert_text I18n.t("events.confirmed_badge"), wait: 5
      click_on I18n.t("events.cancel")
      within("el-dialog") { click_on "Potwierdzam" }
      # After cancel, the waitlister is auto-promoted — event is full again, so
      # the CTA flips to "Dołącz na listę rezerwową" (not "Akceptuję").
      assert_text I18n.t("events.waitlist_accept"), wait: 5
    end

    using_session("promoted_user") do
      # Roster update is live (broadcast_event_updates) — waitlist is now empty,
      # and the promoted user shows up in the confirmed section.
      within "##{roster_id}" do
        assert_text "Lista rezerwowa pusta.", wait: 5
        # "Potwierdzeni" header is styled uppercase by Tailwind.
        within find("h3", text: /Potwierdzeni/i).sibling("ul") do
          assert_text promoted.display_name
        end
      end
    end
  end
end
