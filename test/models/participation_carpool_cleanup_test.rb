require "test_helper"

class ParticipationCarpoolCleanupTest < ActiveSupport::TestCase
  setup do
    @event     = events(:gig-coordinators_tomorrow)
    @driver    = users(:ala)
    @passenger = users(:bartek)
    @driver_part    = Participation.create!(event: @event, user: @driver,    status: :confirmed, position: 1)
    @passenger_part = Participation.create!(event: @event, user: @passenger, status: :confirmed, position: 2)
  end

  test "driver cancelling removes their offer + cascades passenger requests" do
    offer = CarpoolOffer.create!(event: @event, user: @driver)
    CarpoolRequest.create!(carpool_offer: offer, user: @passenger, status: :accepted)

    assert_difference [ "CarpoolOffer.count", "CarpoolRequest.count" ], -1 do
      @driver_part.update!(status: :cancelled)
    end
  end

  test "driver being destroyed removes their offer" do
    CarpoolOffer.create!(event: @event, user: @driver)
    assert_difference "CarpoolOffer.count", -1 do
      @driver_part.destroy
    end
  end

  test "passenger cancelling removes their request but keeps the driver's offer" do
    offer = CarpoolOffer.create!(event: @event, user: @driver)
    CarpoolRequest.create!(carpool_offer: offer, user: @passenger, status: :pending)

    assert_difference "CarpoolRequest.count", -1 do
      assert_no_difference "CarpoolOffer.count" do
        @passenger_part.update!(status: :cancelled)
      end
    end
  end

  test "cancelling only affects carpool artifacts for this event (other events untouched)" do
    other_event = events(:harvest_next_week)
    other_part  = Participation.create!(event: other_event, user: @driver, status: :confirmed, position: 1)

    offer_here  = CarpoolOffer.create!(event: @event,      user: @driver)
    offer_there = CarpoolOffer.create!(event: other_event, user: @driver)

    @driver_part.update!(status: :cancelled)

    refute CarpoolOffer.exists?(offer_here.id), "local offer should have been wiped"
    assert CarpoolOffer.exists?(offer_there.id), "offer on another event must survive"
    assert other_part.reload.confirmed?
  end

  test "passenger cancelling does not disturb other passengers' requests" do
    offer = CarpoolOffer.create!(event: @event, user: @driver)
    CarpoolRequest.create!(carpool_offer: offer, user: @passenger, status: :accepted)

    cezary = users(:cezary)
    Participation.create!(event: @event, user: cezary, status: :confirmed, position: 3)
    other_req = CarpoolRequest.create!(carpool_offer: offer, user: cezary, status: :accepted)

    @passenger_part.update!(status: :cancelled)

    assert CarpoolRequest.exists?(other_req.id)
    assert_equal 1, offer.reload.seats_taken
  end

  test "driver with multiple passengers loses driver role + all passenger links on cancel" do
    cezary = users(:cezary)
    Participation.create!(event: @event, user: cezary, status: :confirmed, position: 3)

    offer = CarpoolOffer.create!(event: @event, user: @driver)
    accepted = CarpoolRequest.create!(carpool_offer: offer, user: @passenger, status: :accepted)
    pending  = CarpoolRequest.create!(carpool_offer: offer, user: cezary,     status: :pending)

    assert CarpoolOffer.exists?(offer.id)
    assert_equal 2, offer.carpool_requests.count

    @driver_part.update!(status: :cancelled)

    refute CarpoolOffer.exists?(offer.id),     "driver role must be wiped when driver cancels participation"
    refute CarpoolRequest.exists?(accepted.id), "accepted passenger request must cascade with the offer"
    refute CarpoolRequest.exists?(pending.id),  "pending passenger request must cascade with the offer"
  end
end
