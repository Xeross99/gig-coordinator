require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "session_ua_labels classifies iPhone Safari" do
    os, browser = session_ua_labels("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1 Safari/604.1")
    assert_equal "iPhone", os
    assert_equal "Safari", browser
  end

  test "session_ua_labels classifies Android Chrome" do
    os, browser = session_ua_labels("Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36")
    assert_equal "Android", os
    assert_equal "Chrome",  browser
  end

  test "session_ua_labels classifies Mac Firefox" do
    os, browser = session_ua_labels("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:120.0) Gecko/20100101 Firefox/120.0")
    assert_equal "Mac",     os
    assert_equal "Firefox", browser
  end

  test "session_ua_labels classifies Windows Edge" do
    os, browser = session_ua_labels("Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0 Safari/537.36 Edg/120.0")
    assert_equal "Windows", os
    assert_equal "Edge",    browser
  end

  test "session_ua_labels detects Chrome on iOS (CriOS) as Chrome" do
    os, browser = session_ua_labels("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1 CriOS/120.0 Mobile/15E148 Safari/604.1")
    assert_equal "iPhone", os
    assert_equal "Chrome", browser
  end

  test "session_ua_labels falls back to Nieznane urządzenie for empty ua" do
    os, browser = session_ua_labels(nil)
    assert_equal "Nieznane urządzenie", os
    assert_nil   browser
  end

  test "session_mobile? is true for iPhone/Android/Mobile user agents" do
    assert session_mobile?("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)")
    assert session_mobile?("Mozilla/5.0 (Linux; Android 13)")
    assert session_mobile?("Mozilla/5.0 (Linux; U; Mobile Safari)")
  end

  test "session_mobile? is false for desktop user agents" do
    refute session_mobile?("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15) Safari/605.1")
    refute session_mobile?("Mozilla/5.0 (Windows NT 10.0) Chrome/120.0")
    refute session_mobile?(nil)
  end
end
