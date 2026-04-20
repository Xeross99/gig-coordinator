require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "valid user can be created" do
    user = User.new(first_name: "Ala", last_name: "Nowak", email: "new-ala@example.com")
    assert user.valid?, user.errors.full_messages.inspect
  end

  test "requires first_name, last_name, email" do
    user = User.new
    refute user.valid?
    assert user.errors[:first_name].any?
    assert user.errors[:last_name].any?
    assert user.errors[:email].any?
  end

  test "email is unique case-insensitively" do
    User.create!(first_name: "A", last_name: "B", email: "u1@example.com")
    dup = User.new(first_name: "C", last_name: "D", email: "U1@EXAMPLE.COM")
    refute dup.valid?
    assert dup.errors.of_kind?(:email, :taken)
  end

  test "email normalized" do
    user = User.create!(first_name: "A", last_name: "B", email: "  UPPER@X.COM ")
    assert_equal "upper@x.com", user.email
  end

  test "has_many participations and push_subscriptions" do
    assert User.reflect_on_association(:participations)
    assert User.reflect_on_association(:push_subscriptions)
  end

  test "title defaults to rookie (0)" do
    user = User.create!(first_name: "A", last_name: "B", email: "fresh@example.com")
    assert_equal "rookie", user.title
  end

  test "title enum exposes all five ranks" do
    assert_equal %w[rookie member veteran captain master], User.titles.keys
  end

  test "display_title returns the i18n-translated label" do
    user = User.new(title: :master)
    assert_equal I18n.t("user.titles.master"), user.display_title
    assert_equal "Mistrz", user.display_title
  end

  test "title_badge_classes returns tier color" do
    assert_equal "bg-gray-100 text-gray-600",     User.new(title: :rookie).title_badge_classes
    assert_equal "bg-green-100 text-green-700",   User.new(title: :member).title_badge_classes
    assert_equal "bg-blue-100 text-blue-700",     User.new(title: :veteran).title_badge_classes
    assert_equal "bg-purple-100 text-purple-700", User.new(title: :captain).title_badge_classes
    assert_equal "bg-yellow-100 text-yellow-800", User.new(title: :master).title_badge_classes
  end

  test "online? is true within ONLINE_WINDOW and false outside" do
    user = users(:ala)
    user.update_column(:last_seen_at, 2.minutes.ago)
    assert user.online?

    user.update_column(:last_seen_at, 10.minutes.ago)
    refute user.online?
  end

  test "online? is false when last_seen_at is nil" do
    user = users(:ala)
    user.update_column(:last_seen_at, nil)
    refute user.online?
  end

  test "welcome email is enqueued on create" do
    assert_enqueued_emails 1 do
      User.create!(first_name: "Nowy", last_name: "User", email: "nowy@example.com")
    end
  end

  test "welcome email is NOT enqueued on update" do
    user = User.create!(first_name: "Up", last_name: "Date", email: "upd@example.com")
    assert_enqueued_emails 0 do
      user.update!(first_name: "Zmieniony")
    end
  end

  test "display_title returns the i18n-translated label for captain" do
    user = User.new(title: :captain)
    assert_equal "Kapitan", user.display_title
  end

  test "master maps to DB value 4 after renumber" do
    assert_equal 4, User.titles["master"]
    assert_equal 3, User.titles["captain"]
  end

  test "managed_hosts returns hosts via host_managers join" do
    user = users(:ala)
    user.managed_hosts << hosts(:jan)
    user.managed_hosts << hosts(:anna)
    assert_equal 2, user.managed_hosts.count
    assert_includes user.managed_hosts, hosts(:jan)
    assert_includes user.managed_hosts, hosts(:anna)
  end

  test "can_create_events? is true for master even without managed_hosts" do
    user = users(:ala)
    user.update!(title: :master)
    assert user.can_create_events?
  end

  test "can_create_events? is true for captain with at least one managed_host" do
    user = users(:ala)
    user.update!(title: :captain)
    user.managed_hosts << hosts(:jan)
    assert user.can_create_events?
  end

  test "can_create_events? is false for captain without managed_hosts" do
    user = users(:ala)
    user.update!(title: :captain)
    refute user.can_create_events?
  end

  test "can_create_events? is false for lower ranks regardless of managed_hosts" do
    user = users(:ala)
    user.managed_hosts << hosts(:jan)
    %i[rookie member veteran].each do |title|
      user.update!(title: title)
      refute user.can_create_events?, "#{title} powinien NIE móc tworzyć eventów"
    end
  end
end
