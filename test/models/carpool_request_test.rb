require "test_helper"

class CarpoolRequestTest < ActiveSupport::TestCase
  setup do
    @event     = events(:gig-coordinators_tomorrow)
    @driver    = users(:ala)
    @passenger = users(:bartek)
    Participation.create!(event: @event, user: @driver,    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @passenger, status: :confirmed, position: 2)
    @offer = CarpoolOffer.create!(event: @event, user: @driver)
  end

  test "valid request from a participant defaults to pending and saves" do
    req = CarpoolRequest.new(carpool_offer: @offer, user: @passenger)
    assert req.valid?, req.errors.full_messages.inspect
    req.save!
    assert req.pending?
  end

  test "driver cannot request their own car" do
    req = CarpoolRequest.new(carpool_offer: @offer, user: @driver)
    refute req.valid?
    assert req.errors[:base].any? { |m| m.include?("samego siebie") }
  end

  test "non-participant cannot request a ride" do
    req = CarpoolRequest.new(carpool_offer: @offer, user: users(:cezary))
    refute req.valid?
    assert req.errors[:base].any? { |m| m.include?("uczestnicy") }
  end

  test "(offer, user) is unique" do
    CarpoolRequest.create!(carpool_offer: @offer, user: @passenger)
    dup = CarpoolRequest.new(carpool_offer: @offer, user: @passenger)
    refute dup.valid?
    assert dup.errors.of_kind?(:user_id, :taken)
  end

  test "cannot accept beyond SEATS cap" do
    @event.update!(capacity: 10) # żeby zmieścić pasażerów w zapisach
    passengers = 5.times.map do |i|
      u = User.create!(first_name: "Pas#{i}", last_name: "Ager#{i}", email: "pas#{i}@example.com")
      Participation.create!(event: @event, user: u, status: :confirmed, position: 10 + i)
      u
    end
    # 4 akceptacje to cap
    reqs = passengers.first(4).map { |u| CarpoolRequest.create!(carpool_offer: @offer, user: u, status: :accepted) }
    assert_equal 4, reqs.size
    assert @offer.reload.full?

    # 5-ty pasażer chce się wbić jako accepted od razu — odrzucone
    overflow = CarpoolRequest.new(carpool_offer: @offer, user: passengers.last, status: :accepted)
    refute overflow.valid?
    assert overflow.errors[:base].any? { |m| m.include?("wolnych miejsc") }

    # Ale jako pending przejdzie
    overflow.status = :pending
    assert overflow.valid?
  end

  test "flipping pending to accepted is blocked when cap reached" do
    @event.update!(capacity: 10)
    users_4 = 4.times.map do |i|
      u = User.create!(first_name: "F#{i}", last_name: "L#{i}", email: "f#{i}@example.com")
      Participation.create!(event: @event, user: u, status: :confirmed, position: 20 + i)
      u
    end
    users_4.each { |u| CarpoolRequest.create!(carpool_offer: @offer, user: u, status: :accepted) }

    extra_user = User.create!(first_name: "Ex", last_name: "Tra", email: "ex@example.com")
    Participation.create!(event: @event, user: extra_user, status: :confirmed, position: 30)
    extra = CarpoolRequest.create!(carpool_offer: @offer, user: extra_user, status: :pending)

    refute extra.update(status: :accepted)
    assert extra.errors[:base].any? { |m| m.include?("wolnych miejsc") }
    assert extra.reload.pending?
  end

  test "enum exposes pending/accepted/declined scopes" do
    r1 = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
    cezary = users(:cezary); Participation.create!(event: @event, user: cezary, status: :confirmed, position: 3)
    r2 = CarpoolRequest.create!(carpool_offer: @offer, user: cezary, status: :accepted)

    assert_includes CarpoolRequest.pending,  r1
    assert_includes CarpoolRequest.accepted, r2
    assert_equal 0, CarpoolRequest.declined.count
  end

  test "destroying the user cascades to their carpool_requests" do
    CarpoolRequest.create!(carpool_offer: @offer, user: @passenger)
    assert_difference "CarpoolRequest.count", -1 do
      @passenger.destroy
    end
  end

  test "a driver on the event cannot request a ride from another driver" do
    # @passenger zostaje kierowcą na tym samym evencie
    @passenger.update!(can_drive: true)
    passenger_offer = CarpoolOffer.create!(event: @event, user: @passenger)
    assert passenger_offer.persisted?

    # Teraz próbuje zapisać się jako pasażer u @driver — walidacja musi to odrzucić
    req = CarpoolRequest.new(carpool_offer: @offer, user: @passenger)
    refute req.valid?
    assert req.errors[:base].any? { |m| m.include?("kierowcą na tym evencie") },
           "spodziewany blad 'kierowcą na tym evencie', mam: #{req.errors[:base].inspect}"
  end

  test "kierowca, który zrezygnuje z funkcji, może stać się pasażerem" do
    @passenger.update!(can_drive: true)
    passenger_offer = CarpoolOffer.create!(event: @event, user: @passenger)
    passenger_offer.destroy

    req = CarpoolRequest.new(carpool_offer: @offer, user: @passenger)
    assert req.valid?, req.errors.full_messages.inspect
  end

  test "bycie kierowcą na INNYM evencie nie blokuje bycia pasażerem tu" do
    other_event = events(:harvest_next_week)
    @passenger.update!(can_drive: true)
    Participation.create!(event: other_event, user: @passenger, status: :confirmed, position: 1)
    CarpoolOffer.create!(event: other_event, user: @passenger)

    req = CarpoolRequest.new(carpool_offer: @offer, user: @passenger)
    assert req.valid?, req.errors.full_messages.inspect
  end
end
