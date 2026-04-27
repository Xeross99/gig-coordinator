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

  test "GET /eventy/:id/czat returns the chat panel with existing messages" do
    Message.create!(event: @event, user: users(:bartek), body: "Pierwsza wiadomość")
    get event_chat_path(@event)
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@event, :chat_panel)}"
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

  test "event show page links to the chat page (no inline chat loaded)" do
    # Hot path: czat nie jest doklejany do strony eventu — jest tylko link
    # do osobnego widoku /eventy/:id/czat w nagłówku.
    get event_path(@event)
    assert_response :success
    assert_select "a[href=?]", event_chat_path(@event)
    assert_select "turbo-frame#event_chat", false
  end
end
