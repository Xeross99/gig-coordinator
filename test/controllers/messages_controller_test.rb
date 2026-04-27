require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:gig-coordinators_tomorrow)
    sign_in_as(users(:ala))
  end

  test "POST requires login" do
    delete session_path
    post event_chat_messages_path(@event), params: { message: { body: "hej" } }
    assert_redirected_to login_path
  end

  test "POST create saves a new message and broadcasts" do
    assert_difference "Message.count", 1 do
      post event_chat_messages_path(@event),
           params: { message: { body: "Cześć wszystkim" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    m = Message.order(:id).last
    assert_equal "Cześć wszystkim", m.body
    assert_equal users(:ala), m.user
    assert_equal @event,       m.event
    assert_response :success
  end

  test "POST create with blank body is rejected" do
    assert_no_difference "Message.count" do
      post event_chat_messages_path(@event),
           params: { message: { body: "" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :unprocessable_content
  end

  test "POST create fallback HTML redirects to chat frame" do
    post event_chat_messages_path(@event), params: { message: { body: "html fallback" } }
    assert_redirected_to event_chat_path(@event)
  end

  test "POST create blocked once event has started" do
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_no_difference "Message.count" do
      post event_chat_messages_path(@event), params: { message: { body: "po starcie" } }
    end
    assert_redirected_to event_path(@event)
    assert_equal I18n.t("events.locked"), flash[:alert]
  end

  test "POST create rate-limits after 20 messages in a minute" do
    Rails.cache.clear
    20.times do |i|
      post event_chat_messages_path(@event),
           params: { message: { body: "msg #{i}" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success, "message #{i} should have passed"
    end

    assert_no_difference "Message.count" do
      post event_chat_messages_path(@event),
           params: { message: { body: "nad limitem" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :too_many_requests
    assert_match I18n.t("participations.rate_limited"), response.body
  ensure
    Rails.cache.clear
  end
end
