require "test_helper"

class EventReminderJobTest < ActiveJob::TestCase
  # Podklasa przechwytująca wysyłkę — pozwala asertować odbiorców i payload
  # bez dotykania prawdziwego web pusha.
  class CapturingNotifier < WebPushNotifier
    def sent = @sent ||= []

    private

    def send_all(subscriptions, payload)
      sent << { user_ids: subscriptions.map(&:user_id), payload: payload }
    end
  end

  setup do
    @host = hosts(:jan)
  end

  # --- SCHEDULOWANIE (callbacki na Event) ---

  test "tworzenie eventu scheduluje przypomnienie na godzinę przed startem" do
    event = create_event(scheduled_at: 1.day.from_now)

    assert_equal 1, reminder_jobs.size
    job = reminder_jobs.first
    args = ActiveJob::Arguments.deserialize(job["arguments"]).last
    assert_equal event.id, args[:event_id]
    assert_equal event.scheduled_at.to_i, args[:scheduled_for].to_i
    assert_equal event.reload.reminder_generation, args[:generation]
    fire_at = Time.zone.parse(job["scheduled_at"].to_s)
    assert_in_delta (event.scheduled_at - EventReminderJob::LEAD_TIME).to_i, fire_at.to_i, 5
  end

  test "sub-event rzutu też dostaje przypomnienie" do
    campaign = EventCampaign.create!(name: "Rzut", host: @host, capacity: 4)
    clear_enqueued_jobs

    sub = create_event(scheduled_at: 1.day.from_now, event_campaign: campaign)

    assert_equal 1, reminder_jobs.size
    args = ActiveJob::Arguments.deserialize(reminder_jobs.first["arguments"]).last
    assert_equal sub.id, args[:event_id]
  end

  test "event utworzony na mniej niż godzinę przed startem — bez przypomnienia" do
    create_event(scheduled_at: 30.minutes.from_now)

    assert_equal 0, reminder_jobs.size
  end

  test "zmiana scheduled_at scheduluje nowy job na nowy termin" do
    event = create_event(scheduled_at: 1.day.from_now)
    clear_enqueued_jobs

    new_time = 2.days.from_now
    event.update!(scheduled_at: new_time, ends_at: new_time + 2.hours)

    assert_equal 1, reminder_jobs.size
    args = ActiveJob::Arguments.deserialize(reminder_jobs.first["arguments"]).last
    assert_equal new_time.to_i, args[:scheduled_for].to_i
    assert_equal 2, args[:generation]
  end

  test "zmiana innego pola nie scheduluje kolejnego przypomnienia" do
    event = create_event
    clear_enqueued_jobs

    event.update!(name: "Inna nazwa")

    assert_equal 0, reminder_jobs.size
  end

  # --- WYKONANIE (idempotencja) ---

  test "stary job po przełożeniu eventu nic nie wysyła (scheduled_for mismatch)" do
    event = create_event(scheduled_at: 1.day.from_now)
    old_time = event.scheduled_at
    old_generation = event.reminder_generation
    new_time = 2.days.from_now
    event.update!(scheduled_at: new_time, ends_at: new_time + 2.hours)
    clear_enqueued_jobs

    EventReminderJob.perform_now(event_id: event.id, scheduled_for: old_time, generation: old_generation)

    assert_no_enqueued_jobs only: WebPushNotifier
  end

  test "aktualny job enqueue'uje WebPushNotifier :event_reminder" do
    event = create_event
    clear_enqueued_jobs

    EventReminderJob.perform_now(event_id: event.id, scheduled_for: event.scheduled_at,
                                 generation: event.reminder_generation)

    assert_enqueued_with(job: WebPushNotifier, args: [ :event_reminder, { event_id: event.id } ])
  end

  test "przełożenie i powrót do pierwotnej godziny (A→B→A) nie dubluje przypomnienia" do
    original_time = 1.day.from_now
    event = create_event(scheduled_at: original_time)
    later_time = original_time + 90.minutes
    event.update!(scheduled_at: later_time, ends_at: later_time + 2.hours)
    event.update!(scheduled_at: original_time, ends_at: original_time + 2.hours)

    # Trzy joby w kolejce (create + dwie zmiany terminu); pierwszy i trzeci
    # mają identyczne scheduled_for — przed fixem oba wysyłały push.
    all_args = reminder_jobs.map { |j| ActiveJob::Arguments.deserialize(j["arguments"]).last }
    assert_equal 3, all_args.size
    clear_enqueued_jobs

    all_args.each { |args| EventReminderJob.perform_now(**args) }

    pushes = enqueued_jobs.select { |j| j["job_class"] == "WebPushNotifier" }
    assert_equal 1, pushes.size
  end

  test "job ze starą generacją no-opuje mimo zgodnego scheduled_for" do
    event = create_event
    clear_enqueued_jobs

    EventReminderJob.perform_now(event_id: event.id, scheduled_for: event.scheduled_at,
                                 generation: event.reminder_generation - 1)

    assert_no_enqueued_jobs only: WebPushNotifier
  end

  test "job sprzed deployu (bez generation) wciąż wysyła po samym scheduled_for" do
    event = create_event
    clear_enqueued_jobs

    EventReminderJob.perform_now(event_id: event.id, scheduled_for: event.scheduled_at)

    assert_enqueued_with(job: WebPushNotifier, args: [ :event_reminder, { event_id: event.id } ])
  end

  test "job no-op dla usuniętego eventu" do
    event = create_event
    scheduled_for = event.scheduled_at
    event.destroy!
    clear_enqueued_jobs

    EventReminderJob.perform_now(event_id: event.id, scheduled_for: scheduled_for)

    assert_no_enqueued_jobs only: WebPushNotifier
  end

  test "job no-op gdy event już wystartował" do
    event = create_event(scheduled_at: 2.hours.from_now)
    event.update_columns(scheduled_at: 5.minutes.ago)
    clear_enqueued_jobs

    EventReminderJob.perform_now(event_id: event.id, scheduled_for: event.scheduled_at)

    assert_no_enqueued_jobs only: WebPushNotifier
  end

  # --- WYSYŁKA (WebPushNotifier :event_reminder) ---

  test "przypomnienie idzie tylko do confirmed, z imieniem w treści" do
    event = create_event
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek), status: :waitlist, position: 1)
    PushSubscription.create!(user: users(:ala), endpoint: "https://push.example/1", p256dh_key: "k", auth_key: "a")
    PushSubscription.create!(user: users(:bartek), endpoint: "https://push.example/2", p256dh_key: "k", auth_key: "a")

    notifier = CapturingNotifier.new
    notifier.perform(:event_reminder, event_id: event.id)

    assert_equal [ [ users(:ala).id ] ], notifier.sent.map { |s| s[:user_ids] }
    payload = notifier.sent.first[:payload]
    assert_includes payload[:title], event.name
    assert_includes payload[:body], users(:ala).first_name
    assert_includes payload[:body], event.scheduled_at.strftime("%H:%M")
  end

  test "wysyłka pomijana gdy event już wystartował" do
    event = create_event
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)
    event.update_columns(scheduled_at: 5.minutes.ago)

    notifier = CapturingNotifier.new
    notifier.perform(:event_reminder, event_id: event.id)

    assert_empty notifier.sent
  end

  private

  def create_event(scheduled_at: 1.day.from_now, **attrs)
    @host.events.create!({ name: "Łapanie", scheduled_at: scheduled_at,
                           ends_at: scheduled_at + 2.hours,
                           pay_per_person: 50, capacity: 2 }.merge(attrs))
  end

  def reminder_jobs
    enqueued_jobs.select { |j| j["job_class"] == "EventReminderJob" }
  end
end
