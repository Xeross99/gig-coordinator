require "test_helper"

class WebPushPoolTest < ActiveSupport::TestCase
  setup do
    WebPushPool.reset!
  end

  teardown do
    WebPushPool.reset!
  end

  test "reuses connections — Net::HTTP created only POOL_SIZE times per host, not per request" do
    new_count = Concurrent::AtomicFixnum.new(0)
    install_mock_connections(new_count: new_count)

    uri = URI.parse("https://fcm.googleapis.com/fcm/send/abc123")
    20.times { WebPushPool.with_connection(uri) { |http| http.request(nil) } }

    assert_equal WebPushPool::POOL_SIZE, new_count.value,
      "Expected #{WebPushPool::POOL_SIZE} connections created and reused across 20 requests"
  end

  test "TLS handshake (start) fires once per pooled connection, not once per request" do
    start_count = Concurrent::AtomicFixnum.new(0)
    install_mock_connections(start_count: start_count)

    uri = URI.parse("https://fcm.googleapis.com/fcm/send/abc123")
    20.times { WebPushPool.with_connection(uri) { |http| http.request(nil) } }

    assert_equal WebPushPool::POOL_SIZE, start_count.value,
      "TLS start should fire #{WebPushPool::POOL_SIZE} times total, not 20"
  end

  test "separate pools per host — two hosts get independent connection sets" do
    new_count = Concurrent::AtomicFixnum.new(0)
    install_mock_connections(new_count: new_count)

    fcm_uri   = URI.parse("https://fcm.googleapis.com/fcm/send/x")
    apple_uri = URI.parse("https://web.push.apple.com/push/y")
    5.times { WebPushPool.with_connection(fcm_uri) { |http| http.request(nil) } }
    5.times { WebPushPool.with_connection(apple_uri) { |http| http.request(nil) } }

    assert_equal 2 * WebPushPool::POOL_SIZE, new_count.value,
      "Two distinct hosts should each get their own pool of #{WebPushPool::POOL_SIZE}"
  end

  test "prewarm opens connections for all subscription endpoints before first push" do
    PushSubscription.create!(user: users(:ala), endpoint: "https://fcm.googleapis.com/fcm/send/prewarm1", p256dh_key: "p", auth_key: "a")
    PushSubscription.create!(user: users(:ala), endpoint: "https://web.push.apple.com/push/prewarm2", p256dh_key: "p", auth_key: "a")

    start_count = Concurrent::AtomicFixnum.new(0)
    install_mock_connections(start_count: start_count)

    WebPushPool.prewarm!
    sleep 0.5

    assert_equal 2 * WebPushPool::POOL_SIZE, start_count.value,
      "Prewarm should start #{WebPushPool::POOL_SIZE} connections per unique push service host"
  ensure
    PushSubscription.where(endpoint: %w[
      https://fcm.googleapis.com/fcm/send/prewarm1
      https://web.push.apple.com/push/prewarm2
    ]).destroy_all
  end

  test "after prewarm, with_connection triggers zero additional TLS handshakes" do
    PushSubscription.create!(user: users(:ala), endpoint: "https://fcm.googleapis.com/fcm/send/prewarm3", p256dh_key: "p", auth_key: "a")

    start_count = Concurrent::AtomicFixnum.new(0)
    install_mock_connections(start_count: start_count)

    WebPushPool.prewarm!
    sleep 0.3
    starts_after_prewarm = start_count.value

    uri = URI.parse("https://fcm.googleapis.com/fcm/send/prewarm3")
    10.times { WebPushPool.with_connection(uri) { |http| http.request(nil) } }

    assert_equal starts_after_prewarm, start_count.value,
      "No new TLS handshakes after prewarm — connections are already started"
  ensure
    PushSubscription.where(endpoint: "https://fcm.googleapis.com/fcm/send/prewarm3").destroy_all
  end

  test "stale connection is replaced transparently on ECONNRESET" do
    request_count = Concurrent::AtomicFixnum.new(0)
    install_mock_connections(on_request: -> {
      request_count.increment
      raise Errno::ECONNRESET if request_count.value == 1
      Net::HTTPCreated.new("1.1", "201", "Created")
    })

    uri = URI.parse("https://fcm.googleapis.com/fcm/send/stale")
    result = nil
    WebPushPool.with_connection(uri) { |http| result = http.request(nil) }

    assert_instance_of Net::HTTPCreated, result, "Should succeed after transparent reconnect"
    assert_operator request_count.value, :>=, 2, "Should have retried after ECONNRESET"
  end

  test "concurrent sends reuse pooled connections without creating extras" do
    new_count = Concurrent::AtomicFixnum.new(0)
    install_mock_connections(new_count: new_count)

    uri = URI.parse("https://fcm.googleapis.com/fcm/send/concurrent")
    pool = Concurrent::FixedThreadPool.new(4)
    20.times do
      pool.post { WebPushPool.with_connection(uri) { |http| http.request(nil) } }
    end
    pool.shutdown
    pool.wait_for_termination(10)

    assert_equal WebPushPool::POOL_SIZE, new_count.value,
      "Even under concurrent load, only #{WebPushPool::POOL_SIZE} connections should exist"
  end

  private

  def install_mock_connections(new_count: nil, start_count: nil, on_request: nil)
    nc, sc, handler = new_count, start_count, on_request

    WebPushPool.instance.define_singleton_method(:build_connection) do |host, port|
      nc&.increment
      http = Net::HTTP.new(host, port)
      started = false
      http.define_singleton_method(:start) { sc&.increment; started = true; self }
      http.define_singleton_method(:started?) { started }
      http.define_singleton_method(:finish) { started = false; self }
      http.define_singleton_method(:request) do |_req|
        handler ? handler.call : Net::HTTPCreated.new("1.1", "201", "Created")
      end
      http
    end
  end
end
