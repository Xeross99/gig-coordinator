require "test_helper"

class CarpoolOffersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:gig_coordinators_tomorrow)
    @user  = users(:ala)
    Participation.create!(event: @event, user: @user, status: :confirmed, position: 1)
  end

  test "POST requires login" do
    post event_carpool_offer_path(@event)
    assert_redirected_to login_path
  end

  test "POST creates an offer for the signed-in participant" do
    sign_in_as(@user)
    assert_difference "CarpoolOffer.count", 1 do
      post event_carpool_offer_path(@event)
    end
    offer = CarpoolOffer.order(:id).last
    assert_equal @user.id,  offer.user_id
    assert_equal @event.id, offer.event_id
    assert_redirected_to event_path(@event)
    assert_match "kierowcą", flash[:notice]
  end

  test "POST refuses if user is not a participant" do
    sign_in_as(users(:bartek))
    assert_no_difference "CarpoolOffer.count" do
      post event_carpool_offer_path(@event)
    end
    assert_redirected_to event_path(@event)
    assert flash[:alert].present?
  end

  test "POST is a no-op on duplicate offer (unique validation)" do
    sign_in_as(@user)
    CarpoolOffer.create!(event: @event, user: @user)
    assert_no_difference "CarpoolOffer.count" do
      post event_carpool_offer_path(@event)
    end
  end

  test "DELETE removes the signed-in user's offer (not other drivers')" do
    sign_in_as(@user)
    bartek = users(:bartek); bartek.update!(can_drive: true)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 2)
    my_offer    = CarpoolOffer.create!(event: @event, user: @user)
    other_offer = CarpoolOffer.create!(event: @event, user: bartek)

    assert_difference "CarpoolOffer.count", -1 do
      delete event_carpool_offer_path(@event)
    end
    refute CarpoolOffer.exists?(my_offer.id)
    assert CarpoolOffer.exists?(other_offer.id)
  end

  test "POST refuses when the user is only on the waitlist" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:waitlist])
    sign_in_as(@user)

    assert_no_difference "CarpoolOffer.count" do
      post event_carpool_offer_path(@event)
    end
    assert_redirected_to event_path(@event)
    assert_match "zapisani uczestnicy", flash[:alert]
  end

  test "POST refuses when the user is a pending reservation" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:reserved])
    sign_in_as(@user)

    assert_no_difference "CarpoolOffer.count" do
      post event_carpool_offer_path(@event)
    end
    assert_redirected_to event_path(@event)
    assert_match "zapisani uczestnicy", flash[:alert]
  end

  test "POST refuses when the user has no driver permission" do
    bartek = users(:bartek); bartek.update!(can_drive: false)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 2)
    sign_in_as(bartek)

    assert_no_difference "CarpoolOffer.count" do
      post event_carpool_offer_path(@event)
    end
    assert_redirected_to event_path(@event)
    assert_match "uprawnień", flash[:alert]
  end

  test "POST blocked once event has started" do
    sign_in_as(@user)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_no_difference "CarpoolOffer.count" do
      post event_carpool_offer_path(@event)
    end
    assert_equal I18n.t("events.locked"), flash[:alert]
  end

  test "DELETE blocked once event has started" do
    sign_in_as(@user)
    offer = CarpoolOffer.create!(event: @event, user: @user)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_no_difference "CarpoolOffer.count" do
      delete event_carpool_offer_path(@event)
    end
    assert CarpoolOffer.exists?(offer.id)
    assert_equal I18n.t("events.locked"), flash[:alert]
  end
end
