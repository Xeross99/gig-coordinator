require "test_helper"

# Wyłączone konto (disabled_at): zero powiadomień (web push + mail),
# zero auto-rezerwacji, brak logowania. Dane i historia zostają.
class UserDisabledAccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @user = users(:bartek)
  end

  test "disable! stampuje disabled_at, ubija sesje i kody logowania" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    LoginCode.generate_for(@user, request: nil)

    @user.disable!

    assert @user.reload.disabled?
    assert_equal 0, @user.sessions.count
    assert_equal 0, @user.login_codes.count
  end

  test "enable! przywraca konto" do
    @user.disable!
    @user.enable!
    refute @user.reload.disabled?
  end

  test "web push omija wyłączone konto (centralny filtr w send_all)" do
    enabled_sub  = PushSubscription.create!(user: users(:cezary), endpoint: "https://example.com/on",
                                            p256dh_key: "p", auth_key: "a")
    disabled_sub = PushSubscription.create!(user: @user, endpoint: "https://example.com/off",
                                            p256dh_key: "p", auth_key: "a")
    @user.disable!

    host  = hosts(:jan)
    event = host.events.create!(name: "Push filtr", scheduled_at: 1.day.from_now,
                                ends_at: 1.day.from_now + 2.hours, pay_per_person: 50, capacity: 4)

    sent = []
    job = WebPushNotifier.new
    job.define_singleton_method(:send_web_push) { |sub, _payload| sent << sub.id }
    job.perform(:event_changed, event_id: event.id, changed_fields: %w[capacity])

    assert_includes sent, enabled_sub.id
    refute_includes sent, disabled_sub.id, "wyłączone konto nie dostaje web pusha"
  end

  test "mailery nie wysyłają do wyłączonego konta" do
    host  = hosts(:jan)
    event = host.events.create!(name: "Mail filtr", scheduled_at: 1.day.from_now,
                                ends_at: 1.day.from_now + 2.hours, pay_per_person: 50, capacity: 4)
    event.participations.destroy_all
    participation = Participation.create!(event: event, user: @user, status: :confirmed, position: 1)
    @user.disable!

    assert_no_emails do
      PromotionMailer.with(participation: participation).notify.deliver_now
      InvitationMailer.with(event: event, user: @user).notify.deliver_now
      LoginCodeMailer.with(record: @user, code: "12345").notify.deliver_now
    end
  end

  test "wyłączony mistrz_piora nie dostaje auto-rezerwacji" do
    mistrz = users(:cezary)
    mistrz.update!(title: :mistrz_piora)
    mistrz.disable!

    host  = hosts(:jan)
    event = host.events.create!(name: "Bez rezerwacji", scheduled_at: 1.day.from_now,
                                ends_at: 1.day.from_now + 2.hours, pay_per_person: 50, capacity: 4)

    assert_equal 0, event.participations.reserved.where(user_id: mistrz.id).count,
                 "seed_on_create nie może zapraszać wyłączonych kont"
  end
end
