require "test_helper"

class HostBlockTest < ActiveSupport::TestCase
  setup do
    @user = users(:ala)
    @host = hosts(:jan)
  end

  test "can create a valid host_block" do
    hb = HostBlock.new(user: @user, host: @host)
    assert hb.valid?, hb.errors.full_messages.inspect
  end

  test "duplicate (user, host) is rejected by unique validation" do
    HostBlock.create!(user: @user, host: @host)
    dup = HostBlock.new(user: @user, host: @host)
    refute dup.valid?
    assert dup.errors.of_kind?(:user_id, :taken)
  end

  test "destroying the user deletes host_blocks" do
    HostBlock.create!(user: @user, host: @host)
    assert_difference "HostBlock.count", -1 do
      @user.destroy
    end
  end

  test "destroying the host deletes host_blocks" do
    HostBlock.create!(user: @user, host: @host)
    assert_difference "HostBlock.count", -1 do
      @host.destroy
    end
  end

  test "User#blocked_from? returns true for blocked host" do
    HostBlock.create!(user: @user, host: @host)
    assert @user.blocked_from?(@host)
    refute @user.blocked_from?(hosts(:anna))
    refute @user.blocked_from?(nil)
  end

  test "Host#blocked_users lists the blocked users" do
    HostBlock.create!(user: @user, host: @host)
    assert_includes @host.blocked_users, @user
  end

  test "User#blocked_hosts lists the blocked hosts" do
    HostBlock.create!(user: @user, host: @host)
    assert_includes @user.blocked_hosts, @host
  end

  test "creating a HostBlock on a master user is rejected" do
    @user.update!(title: :master)
    hb = HostBlock.new(user: @user, host: @host)
    refute hb.valid?
    assert hb.errors[:user].any? { |m| m.include?("Mistrzem Pióra") }
  end

  test "promoting a blocked user to master clears their host_blocks" do
    HostBlock.create!(user: @user, host: @host)
    HostBlock.create!(user: @user, host: hosts(:anna))
    assert_equal 2, @user.host_blocks.count

    @user.update!(title: :master)

    assert_equal 0, @user.reload.host_blocks.count
  end

  test "updating a master without rank change does NOT clear host_blocks" do
    # Sanity: callback ma się uruchomić tylko przy zmianie rangi na master.
    # Nie-mistrz z blokadą, dowolny update (np. last_seen_at) — blokady zostają.
    HostBlock.create!(user: @user, host: @host)
    @user.update!(last_seen_at: Time.current)
    assert_equal 1, @user.reload.host_blocks.count
  end

  test "demoting a master and re-blocking works (invariant nie jest permanentny)" do
    # Najpierw mistrz — nie może dostać blokady.
    @user.update!(title: :master)
    refute HostBlock.new(user: @user, host: @host).valid?
    # Degradacja → można zablokować.
    @user.update!(title: :member)
    assert HostBlock.create!(user: @user, host: @host).persisted?
    # Ponowna promocja → blokada znika automatycznie.
    @user.update!(title: :master)
    assert_equal 0, @user.reload.host_blocks.count
  end

  test "promotion to NON-mistrz rank does NOT clear host_blocks" do
    HostBlock.create!(user: @user, host: @host)
    @user.update!(title: :captain)  # awans, ale nie na mistrza
    assert_equal 1, @user.reload.host_blocks.count
  end
end
