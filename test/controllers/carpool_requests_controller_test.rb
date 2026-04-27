require "test_helper"

class CarpoolRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event     = events(:gig-coordinators_tomorrow)
    @driver    = users(:ala)
    @passenger = users(:bartek)
    @other     = users(:cezary)
    Participation.create!(event: @event, user: @driver,    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @passenger, status: :confirmed, position: 2)
    Participation.create!(event: @event, user: @other,     status: :confirmed, position: 3)
    @offer = CarpoolOffer.create!(event: @event, user: @driver)
  end

  test "POST create requires login" do
    post event_carpool_requests_path(@event), params: { carpool_offer_id: @offer.id }
    assert_redirected_to login_path
  end

  test "POST create enqueues push + mail and persists pending request" do
    sign_in_as(@passenger)
    assert_difference "CarpoolRequest.count", 1 do
      assert_enqueued_with(job: WebPushNotifier) do
        assert_enqueued_emails 1 do
          post event_carpool_requests_path(@event), params: { carpool_offer_id: @offer.id }
        end
      end
    end
    req = CarpoolRequest.order(:id).last
    assert req.pending?
    assert_equal @passenger.id, req.user_id
    assert_equal @offer.id,     req.carpool_offer_id
    assert_redirected_to event_path(@event)
  end

  test "POST create is a no-op on duplicate pending request" do
    sign_in_as(@passenger)
    CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    assert_no_difference "CarpoolRequest.count" do
      post event_carpool_requests_path(@event), params: { carpool_offer_id: @offer.id }
    end
  end

  test "POST create revives a previously declined request back to pending" do
    sign_in_as(@passenger)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :declined)
    post event_carpool_requests_path(@event), params: { carpool_offer_id: @offer.id }
    assert req.reload.pending?
  end

  test "POST create rejects non-participant (passenger is not in the event)" do
    outsider = User.create!(first_name: "Out", last_name: "Sider", email: "out@example.com")
    sign_in_as(outsider)
    assert_no_difference "CarpoolRequest.count" do
      post event_carpool_requests_path(@event), params: { carpool_offer_id: @offer.id }
    end
    assert flash[:alert].present?
  end

  test "POST accept flips status and enqueues push + mail" do
    sign_in_as(@driver)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)

    assert_enqueued_with(job: WebPushNotifier) do
      assert_enqueued_emails 1 do
        post accept_event_carpool_request_path(@event, req)
      end
    end
    assert req.reload.accepted?
    assert_redirected_to event_path(@event)
  end

  test "POST decline flips status and enqueues push + mail" do
    sign_in_as(@driver)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)

    assert_enqueued_with(job: WebPushNotifier) do
      assert_enqueued_emails 1 do
        post decline_event_carpool_request_path(@event, req)
      end
    end
    assert req.reload.declined?
  end

  test "POST accept refuses when car is full" do
    sign_in_as(@driver)
    # Zapełniamy auto do 4 accepted pasażerów
    4.times do |i|
      u = User.create!(first_name: "P#{i}", last_name: "X#{i}", email: "p#{i}@example.com")
      Participation.create!(event: @event, user: u, status: :confirmed, position: 10 + i)
      CarpoolRequest.create!(carpool_offer: @offer, user: u, status: :accepted)
    end

    overflow = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    post accept_event_carpool_request_path(@event, overflow)
    assert overflow.reload.pending?
    assert flash[:alert].to_s.include?("Brak wolnych miejsc")
  end

  test "POST accept by non-driver (somebody else's car) is blocked" do
    sign_in_as(@other)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    post accept_event_carpool_request_path(@event, req)
    assert req.reload.pending?, "request status must not change when a non-driver tries to accept"
    assert flash[:alert].present?
  end

  test "POST decline by non-driver is blocked" do
    sign_in_as(@other)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    post decline_event_carpool_request_path(@event, req)
    assert req.reload.pending?
    assert flash[:alert].present?
  end

  test "DELETE lets the passenger withdraw their own request" do
    sign_in_as(@passenger)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    assert_difference "CarpoolRequest.count", -1 do
      delete event_carpool_request_path(@event, req)
    end
  end

  test "DELETE cannot destroy another passenger's request" do
    sign_in_as(@other)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    assert_no_difference "CarpoolRequest.count" do
      delete event_carpool_request_path(@event, req)
    end
  end

  test "POST create rejects a user who already has their own offer on the event" do
    @passenger.update!(can_drive: true)
    CarpoolOffer.create!(event: @event, user: @passenger)
    sign_in_as(@passenger)

    assert_no_difference "CarpoolRequest.count" do
      post event_carpool_requests_path(@event), params: { carpool_offer_id: @offer.id }
    end
    assert_match "kierowcą na tym evencie", flash[:alert].to_s
  end

  # --- event lock ------------------------------------------------------------

  test "POST create blocked once event has started" do
    sign_in_as(@passenger)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_no_difference "CarpoolRequest.count" do
      post event_carpool_requests_path(@event), params: { carpool_offer_id: @offer.id }
    end
    assert_equal I18n.t("events.locked"), flash[:alert]
  end

  test "POST accept blocked once event has started" do
    sign_in_as(@driver)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    post accept_event_carpool_request_path(@event, req)
    assert req.reload.pending?
    assert_equal I18n.t("events.locked"), flash[:alert]
  end

  test "POST decline blocked once event has started" do
    sign_in_as(@driver)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    post decline_event_carpool_request_path(@event, req)
    assert req.reload.pending?
    assert_equal I18n.t("events.locked"), flash[:alert]
  end

  test "DELETE blocked once event has started" do
    sign_in_as(@passenger)
    req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_no_difference "CarpoolRequest.count" do
      delete event_carpool_request_path(@event, req)
    end
    assert_equal I18n.t("events.locked"), flash[:alert]
  end
end
