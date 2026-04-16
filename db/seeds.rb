# Seed sample data for development. Use `bin/rails db:seed`.
# Idempotent — running multiple times does not duplicate rows.

if Rails.env.development?
  host = Host.find_or_create_by!(email: "jan@example.com") do |h|
    h.first_name = "Jan"
    h.last_name  = "Kowalski"
    h.location   = "Plac Defilad 1, Warszawa"
  end

  other_host = Host.find_or_create_by!(email: "anna@example.com") do |h|
    h.first_name = "Anna"
    h.last_name  = "Nowak"
    h.location   = "Rynek Główny 1, Kraków"
  end

  %w[ala bartek cezary dominika ewa].each do |name|
    User.find_or_create_by!(email: "#{name}@example.com") do |u|
      u.first_name = name.capitalize
      u.last_name  = "Example"
    end
  end

  unless host.events.exists?
    host.events.create!(
      name: "Lapanie kur",
      scheduled_at: 2.days.from_now.change(hour: 8),
      ends_at:      2.days.from_now.change(hour: 11),
      pay_per_person: 150.0,
      capacity: 4
    )
    host.events.create!(
      name: "Zbieranie jabłek",
      scheduled_at: 5.days.from_now.change(hour: 9),
      ends_at:      5.days.from_now.change(hour: 17),
      pay_per_person: 180.0,
      capacity: 6
    )
    other_host.events.create!(
      name: "Koszenie trawy",
      scheduled_at: 3.days.from_now.change(hour: 10),
      ends_at:      3.days.from_now.change(hour: 14),
      pay_per_person: 120.0,
      capacity: 2
    )
  end

  puts "Seeded: #{Host.count} hosts, #{User.count} users, #{Event.count} events."
  puts "Log in with any seeded email — magic-link URL is printed to log/development.log."
end
