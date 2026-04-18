require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  # touch_last_seen stamps the signed-in user's last_seen_at once per minute.
  # The throttle matters: without it every request would write to the DB.

  test "stamps last_seen_at on first signed-in request" do
    user = users(:ala)
    user.update_column(:last_seen_at, nil)

    sign_in_as(user)
    get root_path

    user.reload
    assert user.last_seen_at.present?
    assert_in_delta Time.current, user.last_seen_at, 5
  end

  test "does NOT rewrite last_seen_at within the 1-minute throttle window" do
    user = users(:ala)
    sign_in_as(user)
    get root_path

    user.reload
    stamp = user.last_seen_at
    assert stamp.present?

    # Second request right after the first — stamp should not move.
    get root_path
    user.reload
    assert_equal stamp, user.last_seen_at
  end

  test "rewrites last_seen_at once the throttle window expires" do
    user = users(:ala)
    sign_in_as(user)
    get root_path
    user.reload
    first = user.last_seen_at

    # Simulate the stamp being older than the 1-minute throttle.
    user.update_column(:last_seen_at, 2.minutes.ago)

    get root_path
    user.reload
    assert user.last_seen_at > first - 2.minutes  # updated to "now"
    assert_in_delta Time.current, user.last_seen_at, 5
  end

  test "skips touch_last_seen for anonymous visitors (no session)" do
    # Should not blow up on public pages.
    get login_path
    assert_response :success
  end
end
