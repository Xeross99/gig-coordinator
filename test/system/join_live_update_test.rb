require "application_system_test_case"

class JoinLiveUpdateTest < ApplicationSystemTestCase
  test "user on event show sees counts and roster update live when another user joins" do
    event  = events(:gig-coordinators_tomorrow)
    user_a = users(:bartek)
    user_b = users(:cezary)

    using_session("user_a") do
      sign_in_as(user_a)
      assert_current_path root_path, wait: 5
      click_on event.name
      assert_current_path event_path(event), wait: 5

      within "##{ActionView::RecordIdentifier.dom_id(event, :counts)}" do
        assert_text "0/#{event.capacity}"
      end
      within "##{ActionView::RecordIdentifier.dom_id(event, :roster)}" do
        assert_text "Brak zapisanych."
      end
    end

    using_session("user_b") do
      sign_in_as(user_b)
      click_on event.name
      click_on I18n.t("events.accept")
      assert_text I18n.t("events.confirmed_badge"), wait: 5
    end

    using_session("user_a") do
      within "##{ActionView::RecordIdentifier.dom_id(event, :counts)}" do
        assert_text "1/#{event.capacity}", wait: 5
      end
      within "##{ActionView::RecordIdentifier.dom_id(event, :roster)}" do
        assert_text user_b.display_name, wait: 5
      end
    end
  end
end
