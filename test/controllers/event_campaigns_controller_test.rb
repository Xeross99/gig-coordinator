require "test_helper"

class EventCampaignsControllerTest < ActionDispatch::IntegrationTest
  setup do
    users(:ala).update!(title: :mistrz_piora)
    sign_in_as(users(:ala))
  end

  test "GET /kampanie/nowa wyświetla pusty formularz" do
    get new_event_campaign_path
    assert_response :success
    assert_match "Nowa seria", response.body
  end

  test "POST /kampanie tworzy kampanię z primary capacity" do
    assert_difference -> { EventCampaign.count }, +1 do
      post event_campaigns_path, params: {
        event_campaign: {
          name: "Smoke kampania",
          host_id: hosts(:jan).id,
          capacity: 4
        }
      }
    end
    c = EventCampaign.last
    assert_redirected_to event_campaign_path(c)
    assert_equal "Smoke kampania", c.name
    assert_equal hosts(:jan).id, c.host_id
    assert_equal 4, c.capacity
    assert_equal users(:ala), c.creator
  end

  test "POST /kampanie z 2 nested sub-eventami tworzy je atomowo" do
    sub1_date  = 2.days.from_now.to_date.iso8601
    sub2_date  = 5.days.from_now.to_date.iso8601
    initial_events = Event.count

    post event_campaigns_path, params: {
      event_campaign: {
        name: "Marzec 2026",
        host_id: hosts(:jan).id,
        capacity: 4,
        events_attributes: [
          {
            name: "Łapanie 1",
            event_date: sub1_date,
            start_hour: 7, start_minute: 0,
            duration_hours: 2, duration_minutes: 0,
            pay_per_person: 100, capacity: 4
          },
          {
            name: "Łapanie 2",
            event_date: sub2_date,
            start_hour: 9, start_minute: 30,
            duration_hours: 1, duration_minutes: 30,
            pay_per_person: 150, capacity: 6
          }
        ]
      }
    }

    c = EventCampaign.find_by(name: "Marzec 2026")
    assert_not_nil c, "Kampania nie powstała"
    assert_redirected_to event_campaign_path(c)
    assert_equal initial_events + 2, Event.count
    assert_equal 2, c.events.count

    e1, e2 = c.events.order(:scheduled_at).to_a
    assert_equal "Łapanie 1", e1.name
    assert_equal hosts(:jan).id, e1.host_id  # dziedziczone z kampanii
    assert_equal 4, e1.capacity
    assert_equal "Łapanie 2", e2.name
    assert_equal 6, e2.capacity
  end

  test "POST /kampanie odrzuca twórcę bez uprawnień" do
    users(:ala).update!(title: :kurzy_pacholek, admin: false)
    post event_campaigns_path, params: {
      event_campaign: { name: "Próba", host_id: hosts(:jan).id, capacity: 4 }
    }
    assert_redirected_to root_path
    assert_nil EventCampaign.find_by(name: "Próba")
  end

  test "PATCH /kampanie/:id aktualizuje nazwę kampanii" do
    c = EventCampaign.create!(host: hosts(:jan), name: "Stara", capacity: 4)
    patch event_campaign_path(c), params: {
      event_campaign: { name: "Nowa", host_id: hosts(:jan).id, capacity: 4 }
    }
    c.reload
    assert_redirected_to event_campaign_path(c)
    assert_equal "Nowa", c.name
  end

  test "POST /kampanie nie zapisuje twórcy automatycznie — mistrz dostaje rezerwację jak każdy" do
    post event_campaigns_path, params: {
      event_campaign: { name: "Twórca reserved", host_id: hosts(:jan).id, capacity: 4 }
    }
    c = EventCampaign.last
    cp = c.campaign_participations.find_by(user: users(:ala))
    assert_equal "reserved", cp.status, "twórca-mistrz ma reserved (musi sam akceptować)"
  end

  test "DELETE /kampanie/:id usuwa kampanię i jej sub-eventy" do
    c = EventCampaign.create!(host: hosts(:jan), name: "Do usunięcia", capacity: 4)
    Event.create!(host: hosts(:jan), event_campaign: c, name: "Sub",
                  scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour,
                  pay_per_person: 100, capacity: 4)
    assert_difference -> { EventCampaign.count } => -1, -> { Event.count } => -1 do
      delete event_campaign_path(c)
    end
    assert_redirected_to root_path
  end
end
