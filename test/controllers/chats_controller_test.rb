require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:gig-coordinators_tomorrow)
    sign_in_as(users(:ala))
  end

  test "GET /eventy/:id/czat requires login" do
    delete session_path
    get event_chat_path(@event)
    assert_redirected_to login_path
  end

  test "GET /eventy/:id/czat returns the chat frame with existing messages" do
    Message.create!(event: @event, user: users(:bartek), body: "Pierwsza wiadomość")
    get event_chat_path(@event)
    assert_response :success
    assert_select "turbo-frame#event_chat"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@event, :chat_messages)}" do
      assert_select "li", minimum: 1
    end
    assert_match "Pierwsza wiadomość", response.body
  end

  test "GET /eventy/:id/czat shows empty state when no messages" do
    get event_chat_path(@event)
    assert_response :success
    assert_match "Brak wiadomości", response.body
  end

  test "chat form uses <lexxy-editor> with @-mentions prompt wired to /pracownicy/prompt" do
    get event_chat_path(@event)
    assert_response :success
    assert_select "lexxy-editor[name=?]", "message[body]"
    assert_select "lexxy-prompt[trigger='@'][src=?]", prompt_users_path
  end

  test "event show page renders a lazy turbo-frame for the chat (no messages loaded inline)" do
    # Hot path gwarancja: na stronie eventu sam czat NIE jest ładowany —
    # jest tylko ramka z `src=` i `loading=lazy`, którą Turbo fetchuje osobno.
    get event_path(@event)
    assert_response :success
    assert_select "turbo-frame#event_chat[loading='lazy'][src=?]", event_chat_path(@event)
  end
end
