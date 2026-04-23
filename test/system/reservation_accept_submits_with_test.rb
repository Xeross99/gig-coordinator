require "application_system_test_case"

class ReservationAcceptSubmitsWithTest < ApplicationSystemTestCase
  test "reservation accept button shows turbo-submits-with text and becomes disabled during submit" do
    event = events(:gig-coordinators_tomorrow)
    user  = users(:bartek)

    sign_in_as(user)
    ReservationService.invite!(event, user)

    visit event_path(event)
    assert_text event.name, wait: 5

    accept_btn = page.first("button", exact_text: "Akceptuję")
    refute_nil accept_btn, "expected Akceptuję button to be present"
    assert_equal "Akceptuję…", accept_btn["data-turbo-submits-with"]
    refute accept_btn.disabled?, "button should start enabled"

    # Throttle the network so we can observe the disabled/renamed state mid-request.
    page.driver.browser.network_conditions = { latency: 1500, download_throughput: 10_000, upload_throughput: 10_000 }

    accept_btn.click

    # While the POST is inflight: Turbo adds `disabled` and swaps the label.
    assert_selector "button[disabled]", text: "Akceptuję…", wait: 3

    # Restore network and wait for final redirect to complete.
    page.driver.browser.network_conditions = { latency: 0, download_throughput: 0, upload_throughput: 0 }
    assert_text I18n.t("events.confirmed_badge"), wait: 5
  end
end
