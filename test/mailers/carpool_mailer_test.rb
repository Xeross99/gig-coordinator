require "test_helper"

class CarpoolMailerTest < ActionMailer::TestCase
  setup do
    @event     = events(:gig_coordinators_tomorrow)
    @driver    = users(:ala)
    @passenger = users(:bartek)
    Participation.create!(event: @event, user: @driver,    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @passenger, status: :confirmed, position: 2)
    @offer   = CarpoolOffer.create!(event: @event, user: @driver)
    @request = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :pending)
  end

  def text_body(mail)
    mail.text_part.body.decoded
  end

  test "ask goes to the driver and mentions the passenger + event" do
    mail = CarpoolMailer.with(carpool_request: @request).ask
    assert_equal [ @driver.email ], mail.to
    body = text_body(mail)
    assert_match @passenger.display_name, body
    assert_match @event.name,             body
    assert_match @driver.first_name,      body
  end

  test "accepted goes to the passenger and names the driver" do
    mail = CarpoolMailer.with(carpool_request: @request).accepted
    assert_equal [ @passenger.email ], mail.to
    body = text_body(mail)
    assert_match @driver.display_name, body
    assert_match @event.name,          body
    assert_match @passenger.first_name, body
  end

  test "declined goes to the passenger with explanation" do
    mail = CarpoolMailer.with(carpool_request: @request).declined
    assert_equal [ @passenger.email ], mail.to
    assert_match @event.name, text_body(mail)
  end
end
