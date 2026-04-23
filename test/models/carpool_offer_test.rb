require "test_helper"

class CarpoolOfferTest < ActiveSupport::TestCase
  setup do
    @event = events(:gig-coordinators_tomorrow)
    @user  = users(:ala)
    Participation.create!(event: @event, user: @user, status: :confirmed, position: 1)
  end

  test "valid offer from a confirmed participant saves" do
    offer = CarpoolOffer.new(event: @event, user: @user)
    assert offer.valid?, offer.errors.full_messages.inspect
  end

  test "non-participant cannot offer to drive" do
    offer = CarpoolOffer.new(event: @event, user: users(:bartek))
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("uczestnicy") }
  end

  test "cancelled participant counts as non-participant" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:cancelled])
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
  end

  test "waitlist participant cannot offer to drive" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:waitlist])
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("zapisani uczestnicy") }
  end

  test "reserved participant cannot offer to drive" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:reserved])
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("zapisani uczestnicy") }
  end

  test "offer becomes invalid if participant slips from confirmed onto waitlist" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:waitlist])
    refute offer.reload.valid?
  end

  test "(event, user) is unique" do
    CarpoolOffer.create!(event: @event, user: @user)
    dup = CarpoolOffer.new(event: @event, user: @user)
    refute dup.valid?
    assert dup.errors.of_kind?(:user_id, :taken)
  end

  test "SEATS constant is 4" do
    assert_equal 4, CarpoolOffer::SEATS
  end

  test "seats accounting reflects accepted requests only" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    assert_equal 0, offer.seats_taken
    assert_equal 4, offer.seats_left
    refute offer.full?

    b = users(:bartek); c = users(:cezary); d = users(:dominika)
    [ b, c, d ].each { |u| Participation.create!(event: @event, user: u, status: :confirmed, position: 99) }

    CarpoolRequest.create!(carpool_offer: offer, user: b, status: :pending)   # pending nie liczy
    CarpoolRequest.create!(carpool_offer: offer, user: c, status: :accepted)
    CarpoolRequest.create!(carpool_offer: offer, user: d, status: :declined)  # declined nie liczy

    assert_equal 1, offer.reload.seats_taken
    assert_equal 3, offer.seats_left
    refute offer.full?
  end

  test "destroying the offer cascades to carpool_requests" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    bartek = users(:bartek)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 2)
    CarpoolRequest.create!(carpool_offer: offer, user: bartek, status: :pending)
    assert_difference "CarpoolRequest.count", -1 do
      offer.destroy
    end
  end

  test "destroying the event cascades to offers" do
    CarpoolOffer.create!(event: @event, user: @user)
    assert_difference "CarpoolOffer.count", -1 do
      @event.destroy
    end
  end

  test "destroying the user cascades to their offers" do
    CarpoolOffer.create!(event: @event, user: @user)
    assert_difference "CarpoolOffer.count", -1 do
      @user.destroy
    end
  end

  test "user without can_drive flag cannot create an offer" do
    @user.update!(can_drive: false)
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("uprawnień") }
  end

  test "user with can_drive=true creates offer successfully" do
    @user.update!(can_drive: true)
    assert CarpoolOffer.new(event: @event, user: @user).valid?
  end
end
