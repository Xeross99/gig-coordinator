require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "belongs_to polymorphic authenticatable and generates token on create" do
    user = users(:ala)
    session = Session.create!(authenticatable: user, user_agent: "UA", ip_address: "1.2.3.4")
    assert_equal user, session.authenticatable
    assert_not_nil session.token
    assert_operator session.token.length, :>=, 32
  end

  test "tokens are unique across sessions" do
    user = users(:ala)
    a = Session.create!(authenticatable: user)
    b = Session.create!(authenticatable: user)
    refute_equal a.token, b.token
  end

  test "can belong to a Host" do
    host = hosts(:jan)
    s = Session.create!(authenticatable: host)
    assert_equal host, s.authenticatable
  end
end
