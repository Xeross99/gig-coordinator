require "test_helper"

class CampaignReservationServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @host = hosts(:jan)
    users(:ala).update!(title:      :mistrz_piora)        # rank 4
    users(:bartek).update!(title:   :kurnikowy_gangster)  # rank 2
    users(:cezary).update!(title:   :kurzy_pacholek)      # rank 1
    users(:dominika).update!(title: :zoltodziob)          # rank 0
  end

  def build_campaign(capacity:)
    c = EventCampaign.create!(host: @host, name: "Test kampania", capacity: capacity)
    c.campaign_participations.destroy_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    c
  end

  test "seed_on_create rezerwuje TYLKO mistrzów (brak kaskady na komendantów ani niżej)" do
    c = build_campaign(capacity: 4)
    CampaignReservationService.seed_on_create(c)

    reserved = c.campaign_participations.reserved.includes(:user).order(:position)
    assert_equal 1, reserved.size, "tylko ala jest mistrzem, dostaje 1 rezerwację"
    assert_equal users(:ala), reserved.first.user
    assert reserved.first.reserved_until > Time.current
    assert reserved.first.reserved_until <= Event::RESERVATION_WINDOW.from_now + 1.second
  end

  test "seed_on_create zaprasza wszystkich mistrzów" do
    users(:bartek).update!(title: :mistrz_piora)
    c = build_campaign(capacity: 3)
    CampaignReservationService.seed_on_create(c)

    reserved_users = c.campaign_participations.reserved.includes(:user).order(:position).map(&:user)
    assert_equal 2, reserved_users.size
    assert_equal [ users(:ala), users(:bartek) ].sort_by(&:id), reserved_users.sort_by(&:id)
  end

  test "seed_on_create nie tworzy rezerwacji gdy brak mistrzów" do
    User.where.not(id: users(:dominika).id).destroy_all
    c = build_campaign(capacity: 3)
    CampaignReservationService.seed_on_create(c)
    assert_equal 0, c.campaign_participations.count
  end

  test "refill_one promuje z waitlist najpierw, potem zaprasza kolejnego mistrza" do
    users(:bartek).update!(title: :mistrz_piora)
    c = build_campaign(capacity: 1)
    # Cezary już zapisany na waitliście; jeden slot wolny.
    CampaignParticipation.create!(event_campaign: c, user: users(:cezary),
                                  status: :waitlist, position: 1)
    # Ala potwierdzona, drugi slot rezerwowany.
    CampaignParticipation.create!(event_campaign: c, user: users(:ala),
                                  status: :confirmed, position: 1)
    CampaignParticipation.create!(event_campaign: c, user: users(:bartek),
                                  status: :reserved,  position: 1,
                                  reserved_until: 1.hour.from_now)

    # Bartek odrzuca rezerwację → slot zwolniony.
    bartek = c.campaign_participations.find_by(user: users(:bartek))
    bartek.update!(status: :cancelled, reserved_until: nil)
    c.update!(capacity: 2)  # otwiera drugi slot na confirmed
    CampaignReservationService.refill_one(c)

    cezary_p = c.campaign_participations.find_by(user: users(:cezary))
    assert_equal "confirmed", cezary_p.status, "waitlist promuje się przed kolejnym invitem"
  end

  test "refill_one omija zablokowanych mistrzów" do
    users(:bartek).update!(title: :mistrz_piora)
    c = build_campaign(capacity: 1)
    HostBlock.new(user: users(:ala), host: @host).save(validate: false)
    CampaignReservationService.seed_on_create(c)

    first = c.campaign_participations.reserved.first
    first.update!(status: :cancelled, reserved_until: nil)
    CampaignReservationService.refill_one(c)

    assert_equal 0, c.campaign_participations.reserved.count,
                 "zablokowany mistrz nie może przejąć slotu"
  end

  test "expire_stale! cancel-uje wygasłe rezerwacje i wywołuje refill_one" do
    users(:bartek).update!(title: :mistrz_piora)
    c = build_campaign(capacity: 1)
    p = CampaignParticipation.create!(event_campaign: c, user: users(:ala),
                                      status: :reserved, position: 1,
                                      reserved_until: 1.minute.ago)
    CampaignReservationService.expire_stale!

    p.reload
    assert_equal "cancelled", p.status
    assert_nil p.reserved_until
    # Bartek (drugi mistrz) dostaje rezerwację w refill_one
    assert_equal users(:bartek), c.campaign_participations.reserved.first&.user
  end

  test "fill_open_slots zwiększa primary roster po podniesieniu capacity" do
    users(:bartek).update!(title: :mistrz_piora)
    c = build_campaign(capacity: 1)
    CampaignParticipation.create!(event_campaign: c, user: users(:ala),
                                  status: :confirmed, position: 1)
    c.update!(capacity: 3)
    CampaignReservationService.fill_open_slots(c)

    # Bartek dostaje rezerwację (drugi mistrz, jeszcze nieuczestniczący)
    assert_equal 1, c.campaign_participations.reserved.count
    assert_equal users(:bartek), c.campaign_participations.reserved.first.user
  end

  test "demote_overflow przesuwa nadmiarowych confirmed na początek waitlisty" do
    c = build_campaign(capacity: 4)
    [ :ala, :bartek, :cezary, :dominika ].each_with_index do |key, idx|
      CampaignParticipation.create!(event_campaign: c, user: users(key),
                                    status: :confirmed, position: idx + 1)
    end
    c.update!(capacity: 2)
    CampaignReservationService.demote_overflow(c)

    confirmed = c.campaign_participations.confirmed.order(:position).map(&:user_id)
    waitlist  = c.campaign_participations.waitlist.order(:position).map(&:user_id)
    assert_equal 2, confirmed.size
    assert_equal 2, waitlist.size
  end
end
