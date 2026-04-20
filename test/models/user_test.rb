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

  test "first_name+last_name pair is unique" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "first@example.com")
    dup = User.new(first_name: "Adam", last_name: "Nowak", email: "second@example.com")
    refute dup.valid?
    assert dup.errors.of_kind?(:first_name, :taken)
  end

  test "first_name uniqueness is case-insensitive within the same last_name" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "first2@example.com")
    dup = User.new(first_name: "ADAM", last_name: "Nowak", email: "second2@example.com")
    refute dup.valid?
    assert dup.errors.of_kind?(:first_name, :taken)
  end

  test "same first_name with different last_name is allowed" do
    User.create!(first_name: "Michał", last_name: "Kowalska", email: "a1@example.com")
    other = User.new(first_name: "Michał", last_name: "Wiśniewski", email: "a2@example.com")
    assert other.valid?, other.errors.full_messages.inspect
  end

  test "same last_name with different first_name is allowed" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "b1@example.com")
    other = User.new(first_name: "Piotr", last_name: "Nowak", email: "b2@example.com")
    assert other.valid?, other.errors.full_messages.inspect
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

  test "has :photo attachment with :small variant declared" do
    reflection = User.reflect_on_attachment(:photo)
    assert reflection, ":photo attachment should be defined via Avatarable"
    assert reflection.named_variants.key?(:small), ":small variant should be declared"
  end

  test ":photo can resolve the :small variant on an attached blob" do
    user = users(:ala)
    user.photo.attach(io: StringIO.new("fake"), filename: "avatar.png", content_type: "image/png")
    assert user.photo.attached?
    assert_nothing_raised { user.photo.variant(:small) }
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

  test "event_creator_rank? is true for master" do
    users(:ala).update!(title: :master)
    assert users(:ala).event_creator_rank?
  end

  test "event_creator_rank? is true for captain regardless of managed_hosts" do
    users(:ala).update!(title: :captain)
    assert users(:ala).event_creator_rank?
  end

  test "event_creator_rank? is false for lower ranks" do
    %i[rookie member veteran].each do |title|
      users(:ala).update!(title: title)
      refute users(:ala).event_creator_rank?, "#{title} nie powinien mieć rangi planisty"
    end
  end
end
