require "test_helper"

class EventsHelperTest < ActionView::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "google_maps_embed_src URL-encodes the location" do
    src = google_maps_embed_src("Pawia 112, 43-243 Wisła Mała")
    assert_match "maps.google.com/maps", src
    assert_match "output=embed", src
    assert_match "Pawia+112", URI.decode_www_form_component(src).tr(" ", "+")
  end

  test "google_maps_open_url returns a google.com/maps/search URL" do
    url = google_maps_open_url("Rynek 1, Kraków")
    assert_match "google.com/maps/search/?api=1", url
    assert_match "query=", url
  end

  test "seats_label returns 'miejsce' for exactly 1" do
    assert_equal "miejsce", seats_label(1)
  end

  test "seats_label returns 'miejsca' for 2, 3, 4" do
    [ 2, 3, 4 ].each { |n| assert_equal "miejsca", seats_label(n), "expected 'miejsca' for #{n}" }
  end

  test "seats_label returns 'miejsc' for 0 and 5..21" do
    assert_equal "miejsc", seats_label(0)
    (5..21).each { |n| assert_equal "miejsc", seats_label(n), "expected 'miejsc' for #{n}" }
  end

  test "seats_label returns 'miejsc' for the 12..14 exception" do
    [ 12, 13, 14 ].each { |n| assert_equal "miejsc", seats_label(n), "expected 'miejsc' for #{n}" }
    # Sanity check: 112, 113, 114 also fall into the exception (mod100 12..14)
    [ 112, 113, 114 ].each { |n| assert_equal "miejsc", seats_label(n), "expected 'miejsc' for #{n}" }
  end

  test "seats_label returns 'miejsca' for 22, 23, 24, 32, 33, 34 (mod10 2..4, mod100 not 12..14)" do
    [ 22, 23, 24, 32, 33, 34, 102, 103, 104 ].each do |n|
      assert_equal "miejsca", seats_label(n), "expected 'miejsca' for #{n}"
    end
  end

  test "seats_label returns 'miejsc' for 25..31 and other mod10 0,1,5..9" do
    [ 25, 26, 27, 28, 29, 30, 31, 100, 101, 105 ].each do |n|
      assert_equal "miejsc", seats_label(n), "expected 'miejsc' for #{n}"
    end
  end

  # --- relative_time_chip -----------------------------------------------------

  test "relative_time_chip returns nil for blank input" do
    assert_nil relative_time_chip(nil)
  end

  test "relative_time_chip returns 'zaraz' for <1 min in the future" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "zaraz", relative_time_chip(30.seconds.from_now)
    end
  end

  test "relative_time_chip returns 'przed chwilą' for <1 min in the past" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "przed chwilą", relative_time_chip(30.seconds.ago)
    end
  end

  test "relative_time_chip returns minutes for <1h" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "za 5 min",   relative_time_chip(5.minutes.from_now + 1.second)
      assert_equal "10 min temu", relative_time_chip(10.minutes.ago - 1.second)
    end
  end

  test "relative_time_chip returns hours for <24h" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "za 2 godz.",   relative_time_chip(2.hours.from_now + 1.second)
      assert_equal "3 godz. temu", relative_time_chip(3.hours.ago - 1.second)
    end
  end

  test "relative_time_chip returns 'jutro' when the event is on the next calendar day (>24h ahead)" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "jutro", relative_time_chip(Time.zone.local(2026, 4, 21, 18, 0))
    end
  end

  test "relative_time_chip returns 'wczoraj' when the event was on the previous calendar day (>24h ago)" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "wczoraj", relative_time_chip(Time.zone.local(2026, 4, 19, 6, 0))
    end
  end

  test "relative_time_chip returns days (2..13) in both directions" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "za 3 dni",   relative_time_chip(Time.zone.local(2026, 4, 23, 12, 0))
      assert_equal "5 dni temu", relative_time_chip(Time.zone.local(2026, 4, 15, 12, 0))
      assert_equal "za 13 dni",  relative_time_chip(Time.zone.local(2026, 5,  3, 12, 0))
    end
  end

  test "relative_time_chip returns weeks for 14..29 days out" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "za 2 tyg.",   relative_time_chip(Time.zone.local(2026, 5,  4, 12, 0))
      assert_equal "2 tyg. temu", relative_time_chip(Time.zone.local(2026, 4,  6, 12, 0))
    end
  end

  test "relative_time_chip returns months for 30+ days" do
    travel_to Time.zone.local(2026, 4, 20, 12, 0, 0) do
      assert_equal "za 2 mies.",   relative_time_chip(Time.zone.local(2026, 6, 19, 12, 0))
      assert_equal "2 mies. temu", relative_time_chip(Time.zone.local(2026, 2, 19, 12, 0))
    end
  end

  # --- participation_event_verb ----------------------------------------------

  test "participation_event_verb maps each ParticipationEvent type (męska forma)" do
    assert_equal "zapisał się",          participation_event_verb("joined")
    assert_equal "zapisał się",          participation_event_verb("joined_waitlist")
    assert_equal "anulował udział",      participation_event_verb("cancelled")
    assert_equal "otrzymał zaproszenie", participation_event_verb("reserved")
    assert_equal "przyjął zaproszenie",  participation_event_verb("accepted")
    assert_equal "odrzucił zaproszenie", participation_event_verb("declined")
    assert_equal "wskoczył z rezerwy",   participation_event_verb("promoted")
    assert_equal "rezerwacja wygasła",   participation_event_verb("expired")
  end

  test "participation_event_verb nigdy nie generuje formy żeńskiej" do
    # Inwariant: pracownicy są wyłącznie mężczyznami — verby muszą być w
    # czystej męskiej formie, bez slasha „/a", „/ęła" itd.
    %w[joined joined_waitlist cancelled reserved accepted declined promoted expired].each do |type|
      verb = participation_event_verb(type)
      refute_match %r{/}, verb, "verb dla #{type} ma slash (forma generyczna): #{verb.inspect}"
    end
  end

  # --- participation_status_badge --------------------------------------------

  test "participation_status_badge returns classes + Polish label per status" do
    confirmed = participation_status_badge("confirmed")
    assert_match "emerald", confirmed.first
    assert_equal "Główna lista", confirmed.last

    waitlist = participation_status_badge("waitlist")
    assert_match "amber", waitlist.first
    assert_equal "Rezerwa", waitlist.last

    reserved = participation_status_badge("reserved")
    assert_match "indigo", reserved.first
    assert_equal "Zaproszenie", reserved.last
  end

  test "participation_status_badge accepts symbols too" do
    assert_equal "Główna lista", participation_status_badge(:confirmed).last
  end

  test "participation_status_badge returns nil for statuses without a badge" do
    assert_nil participation_status_badge("cancelled")
    assert_nil participation_status_badge(nil)
  end

  test "history_entry_visuals returns distinct color per ParticipationEvent type" do
    make_entry = ->(type) {
      pe = ParticipationEvent.new(event_type: type)
      { kind: :participation_event, participation_event: pe }
    }
    assert_match "emerald", history_entry_visuals(make_entry.call(:joined)).first
    assert_match "orange",  history_entry_visuals(make_entry.call(:joined_waitlist)).first
    assert_match "emerald", history_entry_visuals(make_entry.call(:promoted)).first
    assert_match "emerald", history_entry_visuals(make_entry.call(:accepted)).first
    assert_match "indigo",  history_entry_visuals(make_entry.call(:reserved)).first
    assert_match "red",     history_entry_visuals(make_entry.call(:declined)).first
    assert_match "red",     history_entry_visuals(make_entry.call(:cancelled)).first
    assert_match "stone",   history_entry_visuals(make_entry.call(:expired)).first
  end

  test "history_entry_visuals: joined and joined_waitlist share the check icon (only color differs)" do
    make_entry = ->(type) {
      pe = ParticipationEvent.new(event_type: type)
      { kind: :participation_event, participation_event: pe }
    }
    joined_color, joined_icon       = history_entry_visuals(make_entry.call(:joined))
    waitlist_color, waitlist_icon   = history_entry_visuals(make_entry.call(:joined_waitlist))
    # Verb stays "zapisał się" for both — only color tells them apart.
    assert_equal joined_icon, waitlist_icon, "ikona dla joined i joined_waitlist musi być ta sama (różni się tylko kolor)"
    refute_equal joined_color, waitlist_color
  end

  test "history_entry_visuals: accepted has a different icon than joined (so 'przyjął zaproszenie' nie wygląda jak 'zapisał się')" do
    make_entry = ->(type) {
      pe = ParticipationEvent.new(event_type: type)
      { kind: :participation_event, participation_event: pe }
    }
    _, joined_icon   = history_entry_visuals(make_entry.call(:joined))
    _, accepted_icon = history_entry_visuals(make_entry.call(:accepted))
    refute_equal joined_icon, accepted_icon,
                 "akceptacja zaproszenia (accepted) musi mieć inną ikonę niż zwykły zapis (joined)"
  end

  test "history_entry_visuals returns stone color for event creation" do
    created = { kind: :created, host: hosts(:jan) }
    color, icon = history_entry_visuals(created)
    assert_match "stone", color
    assert icon.present?
  end

  test "history_entry_text for :created lists host name" do
    created = { kind: :created, host: hosts(:jan) }
    html = history_entry_text(created)
    assert_match "Utworzono zlecenie",     html
    assert_match hosts(:jan).display_name, html
  end

  test "history_entry_text for :participation_event renders user name + verb" do
    participation = Participation.new(user: users(:ala))
    pe = ParticipationEvent.new(event_type: :reserved)
    html = history_entry_text({ kind: :participation_event, participation: participation, participation_event: pe })
    assert_match users(:ala).display_name, html
    assert_match "otrzymał zaproszenie",   html
  end

  # Regresja: historia w panelu gospodarza chodziła przez
  # t("host_panel.history.#{event_type}") i pokrywała 7 z 10 wartości enuma —
  # najczęstszy typ zdarzenia (joined_waitlist) renderował gospodarzowi
  # „Translation missing". i18n nie zgłasza braku klucza, więc nic tego nie
  # łapało. Oba warianty muszą pokrywać PEŁNE enumy obu modeli audytu.
  test "verby historii pokrywają pełne enumy event_type — bez fallbacku" do
    fallback = "zmienił status"
    types = ParticipationEvent.event_types.keys | CampaignParticipationEvent.event_types.keys

    types.each do |type|
      assert_not_equal fallback, host_history_verb(type),
                       "host_history_verb spada na fallback dla #{type}"
      assert_not_equal fallback, participation_event_verb(type),
                       "participation_event_verb spada na fallback dla #{type}"
    end
  end

  test "verby historii nigdy nie generują formy żeńskiej" do
    types = ParticipationEvent.event_types.keys | CampaignParticipationEvent.event_types.keys
    types.each do |type|
      [ host_history_verb(type), participation_event_verb(type) ].each do |verb|
        assert_no_match(/\/a\b|ęła/, verb, "forma żeńska w verbie dla #{type}")
      end
    end
  end
end
