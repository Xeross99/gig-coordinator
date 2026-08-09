require "test_helper"

class CarpoolOfferPassengerTest < ActiveSupport::TestCase
  setup do
    @host = hosts(:jan)
    @event = Event.create!(
      name: "Test carpool", host: @host,
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 3.hours,
      capacity: 6, pay_per_person: 100
    )
    @driver = users(:ala)
    @passenger = users(:bartek)

    @driver.update_column(:can_drive, true)
    @passenger.update_column(:can_drive, true)

    @event.participations.create!(user: @driver, status: :confirmed, position: 1)
    @event.participations.create!(user: @passenger, status: :confirmed, position: 2)

    @offer = @event.carpool_offers.create!(user: @driver)
    @offer.carpool_requests.create!(user: @passenger, status: :accepted)
  end

  test "passenger cannot become driver on the same event" do
    offer = @event.carpool_offers.build(user: @passenger)
    assert_not offer.valid?
    assert_includes offer.errors.full_messages.join, "pasażerem"
  end

  test "user without carpool request can become driver" do
    other = users(:cezary)
    other.update_column(:can_drive, true)
    @event.participations.create!(user: other, status: :confirmed, position: 3)

    offer = @event.carpool_offers.build(user: other)
    assert offer.valid?
  end

  test "user with declined request can become driver" do
    @offer.carpool_requests.where(user: @passenger).update_all(status: :declined)

    offer = @event.carpool_offers.build(user: @passenger)
    assert offer.valid?
  end
end
