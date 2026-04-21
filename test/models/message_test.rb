require "test_helper"

class MessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @event = events(:gig-coordinators_tomorrow)
    @user  = users(:ala)
  end

  test "valid message saves" do
    m = Message.new(event: @event, user: @user, body: "Cześć")
    assert m.valid?
  end

  test "body is required" do
    m = Message.new(event: @event, user: @user, body: "")
    refute m.valid?
  end

  test "body longer than 2000 chars is rejected" do
    m = Message.new(event: @event, user: @user, body: "a" * 2_001)
    refute m.valid?
    assert m.errors.of_kind?(:body, :too_long)
  end

  test "body with only HTML whitespace is rejected (Lexxy empty state)" do
    [ "<p></p>", "<p><br></p>", "<p>   </p>", "<p><br></p><p></p>" ].each do |blank_body|
      m = Message.new(event: @event, user: @user, body: blank_body)
      refute m.valid?, "expected blank for: #{blank_body.inspect}"
      assert m.errors.of_kind?(:body, :blank)
    end
  end

  test "body containing only a mention link (no text) is valid" do
    # User może wysłać wiadomość zawierającą tylko @mention — link jest
    # interaktywny, traktujemy to jako „zawartość".
    m = Message.new(event: @event, user: @user,
                    body: '<p><a href="/pracownicy/1">@Ala</a></p>')
    assert m.valid?, m.errors.full_messages.inspect
  end

  test "messages are ordered by created_at via association" do
    old = Message.create!(event: @event, user: @user, body: "pierwsza", created_at: 1.hour.ago)
    new = Message.create!(event: @event, user: @user, body: "druga")
    assert_equal [ old, new ], @event.reload.messages.to_a
  end

  test "destroying the event cascades to messages" do
    Message.create!(event: @event, user: @user, body: "x")
    assert_difference "Message.count", -1 do
      @event.destroy
    end
  end

  test "destroying the user cascades to messages" do
    Message.create!(event: @event, user: @user, body: "x")
    assert_difference "Message.count", -1 do
      @user.destroy
    end
  end

  test "mentioned_user_ids extracts ids from /pracownicy/:id links" do
    m = Message.new(
      event: @event, user: @user,
      body: '<p>hej <a href="/pracownicy/7">@Bartek</a> i <a href="/pracownicy/8">@Cezary</a></p>'
    )
    assert_equal [ 7, 8 ], m.mentioned_user_ids
  end

  test "mentioned_user_ids skips self-mentions (author nie pinguje siebie)" do
    m = Message.new(
      event: @event, user: @user,
      body: %(<p><a href="/pracownicy/#{@user.id}">@ja</a> cześć</p>)
    )
    assert_empty m.mentioned_user_ids
  end

  test "after_create_commit enqueues WebPushNotifier(:mention) per wspomniany user" do
    assert_enqueued_jobs 1, only: WebPushNotifier do
      Message.create!(event: @event, user: @user,
                      body: %(<p><a href="/pracownicy/#{users(:bartek).id}">@Bartek</a> hej</p>))
    end
    job = enqueued_jobs.find { |j| j["job_class"] == "WebPushNotifier" }
    assert_equal "mention", job["arguments"].first["value"]
    assert_equal users(:bartek).id, job["arguments"].last["user_id"]
  end

  test "after_create_commit nie wywołuje mention-push gdy w body nie ma @mention" do
    assert_no_enqueued_jobs only: WebPushNotifier do
      Message.create!(event: @event, user: @user, body: "<p>hej wszyscy</p>")
    end
  end
end
