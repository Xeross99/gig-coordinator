require "application_system_test_case"

class ReservationPendingCardTest < ApplicationSystemTestCase
  test "feed card flips to the pending-reservation state live when the user is invited" do
    event = events(:gig-coordinators_tomorrow)
    user  = users(:bartek)

    sign_in_as(user)
    assert_current_path root_path, wait: 5

    card_id = ActionView::RecordIdentifier.dom_id(event)
    # Before invite: plain card, no indigo ring on the <li> itself.
    assert_no_selector "##{card_id}.ring-indigo-400"

    # ReservationService.invite! broadcasts a replace to the user-scoped
    # :events stream with `pending_reservation: true`, so the card gets the
    # indigo ring + pulsing dot just for this user.
    ReservationService.invite!(event, user)

    assert_selector "##{card_id}.ring-indigo-400", wait: 5
    within "##{card_id}" do
      assert_text "Rezerwacja oczekuje na Twoje potwierdzenie"
    end
  end
end
