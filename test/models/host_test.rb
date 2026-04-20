require "test_helper"

class HostTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "valid host can be created" do
    host = Host.new(first_name: "Jan", last_name: "Kowalski",
                    email: "new-jan@example.com", location: "Warszawa")
    assert host.valid?, host.errors.full_messages.inspect
  end

  test "requires first_name, last_name, email, location" do
    host = Host.new
    refute host.valid?
    assert host.errors[:first_name].any?
    assert host.errors[:last_name].any?
    assert host.errors[:email].any?
    assert host.errors[:location].any?
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

  test "has_many events and has_one_attached photo" do
    assert Host.reflect_on_association(:events)
    host = Host.new
    assert_respond_to host, :photo
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
end
