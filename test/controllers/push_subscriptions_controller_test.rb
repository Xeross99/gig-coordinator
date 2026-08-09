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

  test "POST re-sync działa jak heartbeat — odświeża updated_at" do
    sub = users(:ala).push_subscriptions.create!(endpoint: "https://x.example/hb", p256dh_key: "p", auth_key: "a")
    sub.update_column(:updated_at, 30.days.ago)

    post push_subscriptions_path, params: {
      push_subscription: { endpoint: "https://x.example/hb", p256dh_key: "p", auth_key: "a" }
    }, as: :json

    assert_response :ok
    assert_in_delta Time.current.to_i, sub.reload.updated_at.to_i, 5
  end

  test "POST przepina endpoint na aktualnego usera (zmiana konta na tym samym urządzeniu)" do
    sub = users(:bartek).push_subscriptions.create!(endpoint: "https://x.example/shared", p256dh_key: "p", auth_key: "a")

    assert_no_difference "PushSubscription.count" do
      post push_subscriptions_path, params: {
        push_subscription: { endpoint: "https://x.example/shared", p256dh_key: "p", auth_key: "a" }
      }, as: :json
    end

    assert_response :ok
    assert_equal users(:ala), sub.reload.user
  end

  test "DELETE po endpoincie w body (pushsubscriptionchange z service workera)" do
    sub = users(:ala).push_subscriptions.create!(endpoint: "https://x.example/rotated-away", p256dh_key: "p", auth_key: "a")

    delete push_subscription_path("rotated"), params: {
      push_subscription: { endpoint: "https://x.example/rotated-away" }
    }, as: :json

    assert_response :no_content
    assert_nil PushSubscription.find_by(id: sub.id)
  end
end
