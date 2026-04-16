require "application_system_test_case"

class AcceptEventLiveUpdateTest < ApplicationSystemTestCase
  test "host sees roster update live when user accepts event" do
    event = events(:gig-coordinators_tomorrow)
    host  = hosts(:jan)
    user  = users(:ala)

    # Host session: visit own event show
    using_session("host") do
      visit verify_magic_link_url(token: host.signed_id(purpose: :magic_link, expires_in: 15.minutes))
      assert_current_path host_root_path
      click_on event.name
      assert_text "Lapanie kur"
      # Before acceptance — no one confirmed
      within "##{ActionView::RecordIdentifier.dom_id(event, :roster)}" do
        assert_text "Brak zapisanych."
      end
    end

    # User session: accept the event
    using_session("user") do
      visit verify_magic_link_url(token: user.signed_id(purpose: :magic_link, expires_in: 15.minutes))
      assert_current_path root_path
      click_on event.name
      click_on I18n.t("events.accept")
      assert_text I18n.t("events.confirmed_badge")
    end

    # Host session: roster has updated without refresh
    using_session("host") do
      within "##{ActionView::RecordIdentifier.dom_id(event, :roster)}" do
        assert_text user.display_name, wait: 5
      end
    end
  end
end
