require "application_system_test_case"

class CancelLiveUpdateTest < ApplicationSystemTestCase
  test "user on event show sees counts and roster update live when another user cancels" do
    event = events(:gig_coordinators_tomorrow)
    # Confirmed cancels są dozwolone tylko gdy lista jest pełna i ktoś
    # czeka w rezerwie — odpowiednio dopełniamy event (capacity=2, dwóch
    # confirmed, jeden waitlist).
    event.update!(capacity: 2)

    user_a   = users(:bartek)    # widz
    user_b   = users(:cezary)    # confirmed → anuluje
    filler   = users(:dominika)  # confirmed (dopełnia capacity)
    promotee = users(:ala)       # waitlist → wskakuje po anulowaniu

    Participation.create!(event: event, user: user_b,   status: :confirmed, position: 1)
    Participation.create!(event: event, user: filler,   status: :confirmed, position: 2)
    Participation.create!(event: event, user: promotee, status: :waitlist,  position: 1)

    using_session("user_a") do
      sign_in_as(user_a)
      click_on event.name
      assert_current_path event_path(event), wait: 5
      within "##{ActionView::RecordIdentifier.dom_id(event, :counts)}" do
        assert_text "2/#{event.capacity}"
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
      # Po anulowaniu waitlist awansuje, lista nadal pełna — CTA flipa na
      # „Dołącz na listę rezerwową", nie na „Akceptuję".
      assert_text I18n.t("events.waitlist_accept"), wait: 5
    end

    using_session("user_a") do
      within "##{ActionView::RecordIdentifier.dom_id(event, :roster)}" do
        # Promowany user pojawia się w sekcji „Potwierdzeni" (uppercase
        # przez Tailwind, więc pasujemy regexem).
        within find("h3", text: /Potwierdzeni/i).sibling("ul") do
          assert_text promotee.display_name, wait: 5
        end
        # A anulujący ma chip „anulował" w sekcji „Wszyscy pracownicy".
        assert_text "anulował"
      end
    end
  end
end
