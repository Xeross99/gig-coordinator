require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  test "valid push_subscription requires user, endpoint, p256dh_key, auth_key" do
    user = users(:ala)
    sub = user.push_subscriptions.new(endpoint: "https://push.example/abc",
                                      p256dh_key: "pkey", auth_key: "akey")
    assert sub.valid?
  end

  test "endpoint is unique" do
    user = users(:ala)
    user.push_subscriptions.create!(endpoint: "https://push.example/uniq",
                                    p256dh_key: "pkey", auth_key: "akey")
    dup = user.push_subscriptions.new(endpoint: "https://push.example/uniq",
                                      p256dh_key: "pkey2", auth_key: "akey2")
    refute dup.valid?
    assert dup.errors[:endpoint].any?
  end
end
