require "test_helper"

class HostManagerTest < ActiveSupport::TestCase
  setup do
    @user = users(:ala)
    @host = hosts(:jan)
  end

  test "can create a valid host_manager" do
    hm = HostManager.new(user: @user, host: @host)
    assert hm.valid?, hm.errors.full_messages.inspect
  end

  test "duplicate (user, host) is rejected by unique validation" do
    HostManager.create!(user: @user, host: @host)
    dup = HostManager.new(user: @user, host: @host)
    refute dup.valid?
    assert dup.errors.of_kind?(:user_id, :taken)
  end

  test "destroying the user deletes host_managers" do
    HostManager.create!(user: @user, host: @host)
    assert_difference "HostManager.count", -1 do
      @user.destroy
    end
  end

  test "destroying the host deletes host_managers" do
    HostManager.create!(user: @user, host: @host)
    assert_difference "HostManager.count", -1 do
      @host.destroy
    end
  end
end
