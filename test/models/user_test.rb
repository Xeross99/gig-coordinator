require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "newly built user has admin=false by default" do
    assert_equal false, User.new.admin
  end

  test "persisting without admin defaults to false" do
    u = User.create!(first_name: "T", last_name: "T", email: "t@t.pl")
    assert_equal false, u.reload.admin
  end

  test "valid user can be created" do
    user = User.new(first_name: "Zofia", last_name: "Kwiatkowska", email: "zofia@example.com")
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

  test "first_name is unique case-insensitively" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "first@example.com")
    dup = User.new(first_name: "adam", last_name: "Kowalski", email: "second@example.com")
    refute dup.valid?
    assert dup.errors.of_kind?(:first_name, :taken)
  end

  test "last_name is unique case-insensitively" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "first2@example.com")
    dup = User.new(first_name: "Piotr", last_name: "NOWAK", email: "second2@example.com")
    refute dup.valid?
    assert dup.errors.of_kind?(:last_name, :taken)
  end

  test "email normalized" do
    user = User.create!(first_name: "A", last_name: "B", email: "  UPPER@X.COM ")
    assert_equal "upper@x.com", user.email
  end

  test "email format is validated" do
    user = User.new(first_name: "A", last_name: "B", email: "not-an-email")
    refute user.valid?
    assert user.errors.of_kind?(:email, :invalid)
  end

  test "updating own record does not conflict with itself on name uniqueness" do
    user = User.create!(first_name: "Self", last_name: "Update", email: "self@example.com")
    user.first_name = "Self"
    user.last_name  = "Update"
    assert user.valid?, user.errors.full_messages.inspect
  end

  test "has_many participations and push_subscriptions" do
    assert User.reflect_on_association(:participations)
    assert User.reflect_on_association(:push_subscriptions)
  end

  test "title defaults to rookie (0)" do
    user = User.create!(first_name: "A", last_name: "B", email: "fresh@example.com")
    assert_equal "rookie", user.title
  end

  test "title enum exposes all four ranks" do
    assert_equal %w[rookie member veteran master], User.titles.keys
  end

  test "display_title returns the i18n-translated label" do
    user = User.new(title: :master)
    assert_equal I18n.t("user.titles.master"), user.display_title
    assert_equal "Mistrz", user.display_title
  end

  test "title_badge_classes returns tier color" do
    assert_equal "bg-gray-100 text-gray-600",     User.new(title: :rookie).title_badge_classes
    assert_equal "bg-green-100 text-green-700",   User.new(title: :member).title_badge_classes
    assert_equal "bg-purple-100 text-purple-700", User.new(title: :veteran).title_badge_classes
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
end
