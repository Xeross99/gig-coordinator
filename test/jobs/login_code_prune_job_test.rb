require "test_helper"

class LoginCodePruneJobTest < ActiveJob::TestCase
  test "kasuje kody starsze niż RETENTION" do
    old = LoginCode.create!(authenticatable: users(:ala), code: "11111",
                            expires_at: 15.minutes.from_now)
    old.update_column(:created_at, LoginCodePruneJob::RETENTION.ago - 1.day)

    assert_difference "LoginCode.count", -1 do
      LoginCodePruneJob.perform_now
    end
    refute LoginCode.exists?(old.id)
  end

  test "zostawia świeże kody — także już zużyte" do
    fresh  = LoginCode.create!(authenticatable: users(:ala), code: "22222",
                               expires_at: 15.minutes.from_now)
    used   = LoginCode.create!(authenticatable: users(:bartek), code: "33333",
                               expires_at: 15.minutes.from_now, used_at: Time.current)

    assert_no_difference "LoginCode.count" do
      LoginCodePruneJob.perform_now
    end
    assert LoginCode.exists?(fresh.id)
    assert LoginCode.exists?(used.id)
  end
end
