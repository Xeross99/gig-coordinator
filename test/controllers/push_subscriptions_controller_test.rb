require "test_helper"

class PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:ala)) }

  test "POST requires login" do
    delete session_path
    post push_subscriptions_path, params: { push_subscription: { endpoint: "x", p256dh_key: "x", auth_key: "x" } }, as: :json
    assert_response :unauthorized
  end

  test "POST creates subscription for current_user (JSON)" do
    assert_difference "PushSubscription.count", 1 do
      post push_subscriptions_path, params: {
        push_subscription: {
          endpoint: "https://fcm.googleapis.com/fcm/send/abc123",
          p256dh_key: "pkey",
          auth_key: "akey"
        }
      }, as: :json
    end
    assert_response :created
    assert_equal users(:ala), PushSubscription.last.user
  end

  test "POST is idempotent (same endpoint) - returns existing" do
    post push_subscriptions_path, params: {
      push_subscription: { endpoint: "https://x.example/e", p256dh_key: "p", auth_key: "a" }
    }, as: :json
    assert_no_difference "PushSubscription.count" do
      post push_subscriptions_path, params: {
        push_subscription: { endpoint: "https://x.example/e", p256dh_key: "p", auth_key: "a" }
      }, as: :json
    end
    assert_response :ok
  end

  test "DELETE removes current_user subscription by endpoint" do
    sub = users(:ala).push_subscriptions.create!(endpoint: "https://e/a", p256dh_key: "p", auth_key: "a")
    delete push_subscription_path(sub), as: :json
    assert_response :no_content
    assert_nil PushSubscription.find_by(id: sub.id)
  end
end
