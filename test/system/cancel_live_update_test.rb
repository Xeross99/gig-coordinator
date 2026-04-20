require "application_system_test_case"

class CancelLiveUpdateTest < ApplicationSystemTestCase
  test "user on event show sees counts and roster update live when another user cancels" do
    event  = events(:gig-coordinators_tomorrow)
    user_a = users(:bartek)
    user_b = users(:cezary)

    # Seed B as a confirmed participant so the cancel button is visible.
    Participation.create!(event: event, user: user_b, status: :confirmed, position: 1)

    using_session("user_a") do
      sign_in_as(user_a)
      click_on event.name
      assert_current_path event_path(event), wait: 5
      within "##{ActionView::RecordIdentifier.dom_id(event, :counts)}" do
        assert_text "1/#{event.capacity}"
      end
      within "##{ActionView::RecordIdentifier.dom_id(event, :roster)}" do
        assert_text user_b.display_name
      end
    end

    using_session("user_b") do
      sign_in_as(user_b)
      click_on event.name
      assert_text I18n.t("events.confirmed_badge"), wait: 5
      click_on I18n.t("events.cancel")
      # Custom el-dialog confirmation replaces the native browser confirm.
      within("el-dialog") { click_on "Potwierdzam" }
      assert_text I18n.t("events.accept"), wait: 5 # button flipped back to join CTA
    end

    using_session("user_a") do
      within "##{ActionView::RecordIdentifier.dom_id(event, :counts)}" do
        assert_text "0/#{event.capacity}", wait: 5
      end
      within "##{ActionView::RecordIdentifier.dom_id(event, :roster)}" do
        # Confirmed section flips back to empty. (The "Wszyscy pracownicy"
        # panel still lists every user — now with an "anulował" chip next to
        # user_b — so we don't assert absence of the name globally.)
        assert_text "Brak zapisanych.", wait: 5
        assert_text "anulował"
      end
    end
  end
end
