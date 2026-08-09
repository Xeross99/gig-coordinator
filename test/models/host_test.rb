require "test_helper"

class HostTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "valid host can be created" do
    host = Host.new(first_name: "Zenon", last_name: "Kurczak",
                    email: "zenon@example.com", location: "Warszawa")
    assert host.valid?, host.errors.full_messages.inspect
  end

  test "requires first_name, last_name, location (email is optional)" do
    host = Host.new
    refute host.valid?
    assert host.errors[:first_name].any?
    assert host.errors[:last_name].any?
    assert host.errors[:location].any?
    assert_empty host.errors[:email]
  end

  test "email is unique case-insensitively" do
    Host.create!(first_name: "A", last_name: "B", email: "uniq@example.com", location: "L")
    dup = Host.new(first_name: "C", last_name: "D", email: "UNIQ@EXAMPLE.COM", location: "L")
    refute dup.valid?
    assert dup.errors.of_kind?(:email, :taken)
  end

  test "email is normalized to lowercase + stripped" do
    host = Host.create!(first_name: "A", last_name: "B", email: "  NORM@Example.COM ", location: "L")
    assert_equal "norm@example.com", host.email
  end

  test "blank email is normalized to nil so multiple hosts can have no email" do
    h1 = Host.create!(first_name: "NoMail", last_name: "One", email: "", location: "L1")
    h2 = Host.new(first_name: "NoMail", last_name: "Two", location: "L2")  # no email at all
    assert_nil h1.email
    assert h2.valid?, h2.errors.full_messages.inspect
  end

  test "has_many events and has_one_attached photo" do
    assert Host.reflect_on_association(:events)
    host = Host.new
    assert_respond_to host, :photo
  end

  test "has :photo attachment with :small variant declared (via Avatarable)" do
    reflection = Host.reflect_on_attachment(:photo)
    assert reflection
    assert reflection.named_variants.key?(:small)
  end

  test ":photo can resolve the :small variant on an attached blob" do
    host = hosts(:jan)
    host.photo.attach(io: StringIO.new("fake"), filename: "avatar.png", content_type: "image/png")
    assert host.photo.attached?
    assert_nothing_raised { host.photo.variant(:small) }
  end

  test "no welcome email is enqueued on create (hosts onboard via console)" do
    assert_enqueued_emails 0 do
      Host.create!(first_name: "New", last_name: "Host", email: "nh@example.com", location: "Somewhere")
    end
  end

  test "managers returns users via host_managers join" do
    host = hosts(:jan)
    host.managers << users(:ala)
    host.managers << users(:bartek)
    assert_equal 2, host.managers.count
    assert_includes host.managers, users(:ala)
    assert_includes host.managers, users(:bartek)
  end

  test "phone is optional" do
    host = Host.new(first_name: "Bez", last_name: "Tel", location: "L")
    assert host.valid?, host.errors.full_messages.inspect
    assert_nil host.phone
  end

  test "phone is stripped of surrounding whitespace" do
    host = Host.create!(first_name: "Z", last_name: "Tel", location: "L", phone: "  +48 987 654 321  ")
    assert_equal "+48 987 654 321", host.phone
  end

  test "blank phone is normalized to nil" do
    host = Host.create!(first_name: "Pusty", last_name: "Tel", location: "L", phone: "   ")
    assert_nil host.phone
  end
end
