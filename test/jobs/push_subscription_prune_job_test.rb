require "test_helper"

class PushSubscriptionPruneJobTest < ActiveJob::TestCase
  setup do
    @user = users(:ala)
  end

  test "kasuje zombie — starą subskrypcję usera, który ma świeższą" do
    zombie = build_sub("https://push.example/zombie", seen: 90.days.ago)
    fresh  = build_sub("https://push.example/fresh",  seen: 1.day.ago)

    PushSubscriptionPruneJob.perform_now

    assert_nil PushSubscription.find_by(id: zombie.id)
    assert PushSubscription.exists?(fresh.id)
  end

  test "NIE kasuje starej subskrypcji, gdy to jedyny kanał usera" do
    only_one = build_sub("https://push.example/lonely", seen: 90.days.ago)

    PushSubscriptionPruneJob.perform_now

    assert PushSubscription.exists?(only_one.id), "user nie może zostać całkiem uciszony"
  end

  test "świeższa subskrypcja INNEGO usera nie liczy się jako zamiennik" do
    stale = build_sub("https://push.example/stale", seen: 90.days.ago)
    PushSubscription.create!(user: users(:bartek), endpoint: "https://push.example/other-guy",
                             p256dh_key: "p", auth_key: "a")

    PushSubscriptionPruneJob.perform_now

    assert PushSubscription.exists?(stale.id)
  end

  test "subskrypcje młodsze niż STALE_AFTER zostają" do
    a = build_sub("https://push.example/a", seen: 40.days.ago)
    b = build_sub("https://push.example/b", seen: 1.hour.ago)

    PushSubscriptionPruneJob.perform_now

    assert PushSubscription.exists?(a.id)
    assert PushSubscription.exists?(b.id)
  end

  private

  def build_sub(endpoint, seen:)
    sub = @user.push_subscriptions.create!(endpoint: endpoint, p256dh_key: "p", auth_key: "a")
    sub.update_column(:updated_at, seen)
    sub
  end
end
