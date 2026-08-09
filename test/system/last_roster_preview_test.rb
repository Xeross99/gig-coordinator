require "application_system_test_case"

class LastRosterPreviewTest < ApplicationSystemTestCase
  test "mistrz_piora widzi skład poprzedniego ukończonego eventu po wyborze hosta" do
    users(:ala).update!(title: :mistrz_piora)

    past = Event.create!(host: hosts(:jan), name: "Łapanie poprzednie",
                         scheduled_at: 4.days.ago, ends_at: 4.days.ago + 2.hours,
                         pay_per_person: 100, capacity: 3)
    Participation.create!(event: past, user: users(:bartek),   status: :confirmed, position: 1)
    Participation.create!(event: past, user: users(:dominika), status: :waitlist,  position: 1)

    sign_in_as(users(:ala))
    assert_current_path root_path, wait: 5
    visit new_event_path
    assert_current_path new_event_path, wait: 5

    within "#last-roster-preview" do
      assert_text "Wybierz gospodarza"
    end

    select hosts(:jan).display_name, from: "event_host_id"

    # Stimulus debounce 150 ms + fetch — Capybara czeka.
    within "#last-roster-preview" do
      assert_text "Łapanie poprzednie"
      assert_text users(:bartek).display_name
      assert_text users(:dominika).display_name
      assert_text "potwierdzony"
      assert_text "rezerwa"
    end
  end
end
