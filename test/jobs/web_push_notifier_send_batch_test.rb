require "test_helper"

class WebPushNotifierSendBatchTest < ActiveJob::TestCase
  setup do
    @user = users(:ala)
    @sub1 = PushSubscription.create!(user: @user, endpoint: "https://example.com/batch/1", p256dh_key: "p", auth_key: "a")
    @sub2 = PushSubscription.create!(user: @user, endpoint: "https://example.com/batch/2", p256dh_key: "p", auth_key: "a")
    @job = WebPushNotifier.new
  end

  # --- send_batch concurrency -----------------------------------------------

  test "send_batch delivers to all subscriptions" do
    sent = Concurrent::Array.new
    @job.define_singleton_method(:send_web_push) { |sub, _payload, **| sent << sub.id }

    @job.send(:send_batch, PushSubscription.where(user: @user), { title: "test" })

    assert_equal [ @sub1.id, @sub2.id ].sort, sent.sort
  end

  test "one subscription error does not block others in send_batch" do
    sent = Concurrent::Array.new
    failing_id = @sub1.id
    @job.define_singleton_method(:send_web_push) do |sub, _payload, **|
      raise RuntimeError, "kaboom" if sub.id == failing_id
      sent << sub.id
    end

    @job.send(:send_batch, PushSubscription.where(user: @user), { title: "test" })

    assert_equal [ @sub2.id ], sent
  end
end
