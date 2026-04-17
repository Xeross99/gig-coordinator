require "test_helper"

class LoginCodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:ala)
  end

  test "generate_for creates a 5-digit code with 15-minute expiry" do
    freeze_time do
      code = LoginCode.generate_for(@user)
      assert_match(/\A\d{5}\z/, code.code)
      assert_equal @user, code.authenticatable
      assert_equal 15.minutes.from_now, code.expires_at
      assert_nil code.used_at
      assert_equal 0, code.attempts
    end
  end

  test "generate_for invalidates previous active codes for the same record" do
    first = LoginCode.generate_for(@user)
    assert_nil first.used_at

    second = LoginCode.generate_for(@user)

    first.reload
    assert_not_nil first.used_at, "previous code should be marked used"
    assert_nil second.used_at
    assert_not_equal first.code, second.code
  end

  test "active scope excludes used, expired, and max-attempts codes" do
    # Build each directly to avoid generate_for's cascading invalidation
    fresh = LoginCode.create!(
      authenticatable: @user,
      code:            "11111",
      expires_at:      10.minutes.from_now
    )
    used = LoginCode.create!(
      authenticatable: @user,
      code:            "22222",
      expires_at:      10.minutes.from_now,
      used_at:         Time.current
    )
    expired = LoginCode.create!(
      authenticatable: @user,
      code:            "33333",
      expires_at:      1.minute.ago
    )
    maxed = LoginCode.create!(
      authenticatable: @user,
      code:            "44444",
      expires_at:      10.minutes.from_now,
      attempts:        LoginCode::MAX_ATTEMPTS
    )

    active = LoginCode.for(@user).active.to_a
    assert_includes active, fresh
    refute_includes active, used
    refute_includes active, expired
    refute_includes active, maxed
  end

  test "consume with correct code returns it and marks it used" do
    code = LoginCode.generate_for(@user)
    result = LoginCode.consume(@user, code.code)
    assert_equal code, result
    assert_not_nil code.reload.used_at
  end

  test "consume with wrong code increments attempts on the active code" do
    code = LoginCode.generate_for(@user)
    assert_nil LoginCode.consume(@user, "99999")
    assert_equal 1, code.reload.attempts
    assert_nil code.used_at
  end

  test "consume kills the active code after MAX_ATTEMPTS failed tries" do
    code = LoginCode.generate_for(@user)
    (LoginCode::MAX_ATTEMPTS).times { LoginCode.consume(@user, "99999") }
    code.reload
    assert_equal LoginCode::MAX_ATTEMPTS, code.attempts
    assert_not_nil code.used_at, "code should be burned after max attempts"

    # even the correct code now fails
    assert_nil LoginCode.consume(@user, code.code)
  end

  test "consume returns nil when no active code exists" do
    assert_nil LoginCode.consume(@user, "12345")
  end
end
