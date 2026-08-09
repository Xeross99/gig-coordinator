require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "manifest is served as JSON with brand name" do
    get pwa_manifest_path
    assert_response :success
    assert_includes response.media_type, "json"
    assert_includes response.body, "Gig Coordinator"
  end

  test "service worker is served as JavaScript with push handler" do
    get pwa_service_worker_path
    assert_response :success
    assert_includes response.media_type, "javascript"
    assert_includes response.body, "addEventListener(\"push\""
  end

  test "manifest is reachable without a browser User-Agent (bypasses allow_browser :modern)" do
    get pwa_manifest_path, headers: { "User-Agent" => "" }
    assert_response :success
    assert_includes response.body, "Gig Coordinator"
  end
end
