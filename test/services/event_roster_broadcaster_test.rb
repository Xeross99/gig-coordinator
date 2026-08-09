require "test_helper"

class EventRosterBroadcasterTest < ActiveSupport::TestCase
  setup do
    @host  = hosts(:jan)
    @event = Event.create!(host: @host, name: "Test",
                           scheduled_at: 1.day.from_now,
                           ends_at:      1.day.from_now + 2.hours,
                           pay_per_person: 100, capacity: 4)
    @event.participations.delete_all
    Participation.create!(event: @event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:cezary), status: :confirmed, position: 3)
    users(:ala).update!(can_drive: true)
    @offer = CarpoolOffer.create!(event: @event, user: users(:ala))
  end

  # Podmienia `Turbo::StreamsChannel.broadcast_replace_to` na łapacz argumentów
  # — tak żeby test mógł zweryfikować jakie streamy poszły, BEZ realnego
  # broadcastu przez ActionCable.
  def capture_broadcasts
    captured = []
    original = Turbo::StreamsChannel.method(:broadcast_replace_to)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) do |stream_name, **opts|
      captured << { stream: Array(stream_name), opts: opts }
    end
    yield captured
  ensure
    Turbo::StreamsChannel.singleton_class.send(:remove_method, :broadcast_replace_to)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to, original)
  end

  test "broadcast sends per-driver stream targeted at [event, driver, :roster_personal]" do
    streams = nil
    capture_broadcasts do |captured|
      EventRosterBroadcaster.broadcast(@event)
      streams = captured
    end

    generic = streams.first
    assert_includes generic[:stream], @event
    assert_equal :roster, generic[:stream].last
    assert generic[:opts][:html].present?, "generic leci jako gotowy HTML (default render bez Current.user)"

    personal = streams.find { |s| s[:stream].last == :roster_personal && s[:stream].include?(users(:ala)) }
    refute_nil personal, "musi pójść broadcast na [event, driver, :roster_personal]"
    assert personal[:opts][:html].present?, "per-driver leci jako gotowy HTML"
  end

  test "broadcast wysyła personal stream do każdego confirmed uczestnika (nie tylko driverów/pasażerów)" do
    # bartek / cezary są confirmed, nie są ani kierowcami, ani pasażerami.
    # Powinni dostać własny stream — w show.html.erb subskrybują tylko personal,
    # więc bez tego nie dostaliby żadnego live update.
    captured_personal_user_ids = nil
    capture_broadcasts do |captured|
      EventRosterBroadcaster.broadcast(@event)
      captured_personal_user_ids = captured
                                     .select { |s| s[:stream].last == :roster_personal }
                                     .flat_map { |s| s[:stream] }
                                     .grep(User)
                                     .map(&:id)
    end

    assert_includes captured_personal_user_ids, users(:ala).id, "kierowca dostaje personal"
    assert_includes captured_personal_user_ids, users(:bartek).id, "confirmed bez carpool roli też dostaje personal"
    assert_includes captured_personal_user_ids, users(:cezary).id, "kolejny confirmed też"
  end

  test "per-driver render shows driver's action UI even though Current differs at broadcast time" do
    # Symulujemy realną sytuację: pasażer tworzy CarpoolRequest → broadcast
    # leci z Current.user = pasażer, ale wersja per-driver musi pokazać
    # przyciski (z perspektywy kierowcy).
    Current.session = Session.new(authenticatable: users(:bartek))
    CarpoolRequest.create!(carpool_offer: @offer, user: users(:bartek))

    captured_html = nil
    capture_broadcasts do |captured|
      EventRosterBroadcaster.broadcast(@event.reload)
      personal = captured.find do |s|
        s[:stream].last == :roster_personal && s[:stream].include?(users(:ala))
      end
      captured_html = personal[:opts][:html]
    end

    refute_nil captured_html
    assert_match "Zapytania", captured_html, "kierowca widzi nagłówek 'Zapytania' (nie pasywne 'osób czeka')"
    assert_match "Potwierdź", captured_html, "kierowca widzi przycisk Potwierdź"
    assert_match "Odrzuć",   captured_html, "kierowca widzi przycisk Odrzuć"
  ensure
    Current.session = nil
  end

  test "broadcast restores Current.session after rendering per-driver views" do
    original_session = Session.new(authenticatable: users(:bartek))
    Current.session = original_session

    EventRosterBroadcaster.broadcast(@event)

    assert_equal original_session, Current.session
  ensure
    Current.session = nil
  end
end
