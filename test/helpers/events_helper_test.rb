require "test_helper"

class EventsHelperTest < ActionView::TestCase
  test "google_maps_embed_src URL-encodes the location" do
    src = google_maps_embed_src("Słoneczna 12, 00-001 Warszawa")
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

  test "participation_action_verb maps each (status, phase) pair" do
    assert_equal "dołączył jako potwierdzony",       participation_action_verb("confirmed", :initial)
    assert_equal "został potwierdzony",              participation_action_verb("confirmed", :update)
    assert_equal "zapisał się na listę rezerwową",   participation_action_verb("waitlist",  :initial)
    assert_equal "przeniesiony na listę rezerwową",  participation_action_verb("waitlist",  :update)
    assert_equal "otrzymał zaproszenie",             participation_action_verb("reserved",  :initial)
    assert_equal "ponownie zaproszony",              participation_action_verb("reserved",  :update)
    assert_equal "anulował udział",                  participation_action_verb("cancelled", :initial)
    assert_equal "anulował udział",                  participation_action_verb("cancelled", :update)
  end

  test "participation_action_verb never mentions the word rezerwacja for invites" do
    # Reserved participations should be rendered as invitations, never as
    # "rezerwacja" (product decision — don't mix reservations with bookings).
    refute_match(/rezerwac/i, participation_action_verb("reserved", :initial))
    refute_match(/rezerwac/i, participation_action_verb("reserved", :update))
  end

  test "history_entry_visuals returns distinct color per participation status" do
    make_entry = ->(status) {
      p = Participation.new(status: status)
      { kind: :joined, participation: p }
    }
    assert_match "emerald", history_entry_visuals(make_entry.call(:confirmed)).first
    assert_match "amber",   history_entry_visuals(make_entry.call(:waitlist)).first
    assert_match "indigo",  history_entry_visuals(make_entry.call(:reserved)).first
    assert_match "red",     history_entry_visuals(make_entry.call(:cancelled)).first
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
    assert_match "Utworzono wydarzenie",     html
    assert_match hosts(:jan).display_name, html
  end

  test "history_entry_text for :joined uses the initial-phase verb" do
    participation = Participation.new(user: users(:ala), status: :confirmed)
    html = history_entry_text({ kind: :joined, participation: participation })
    assert_match users(:ala).display_name,     html
    assert_match "dołączył jako potwierdzony", html
  end

  test "history_entry_text for :status_change uses the update-phase verb" do
    participation = Participation.new(user: users(:ala), status: :confirmed)
    html = history_entry_text({ kind: :status_change, participation: participation })
    assert_match users(:ala).display_name, html
    assert_match "został potwierdzony",    html
  end
end
