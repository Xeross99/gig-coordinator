# Seed sample data for development. Use `bin/rails db:seed`.
# Idempotent — running multiple times does not duplicate rows.

if Rails.env.development?
  host = Host.find_or_create_by!(email: "jan@example.com") do |h|
    h.first_name = "Jan"
    h.last_name  = "Kowalski"
    h.location   = "Słoneczna 12, 00-001 Warszawa"
  end

  [
    { first_name: "Michał",   last_name: "Kowalska",  email: "admin@gigcoordinator.pl",       title: 3 },
    { first_name: "Adam",     last_name: "Nowak",      email: "example@gigcoordinator.pl",     title: 3 },
    { first_name: "Michał",   last_name: "Wiśniewski",  email: "example2@gigcoordinator.pl",    title: 0 },
    { first_name: "Marcin",   last_name: "Lewandowski",       email: "example3@gigcoordinator.pl",    title: 1 },
    { first_name: "Mateusz",  last_name: "Zieliński",  email: "example4@gigcoordinator.pl",    title: 2 },
    { first_name: "Ksawery",  last_name: "Szymański",     email: "example5@gigcoordinator.pl",    title: 1 }
  ].each do |attrs|
    User.find_or_create_by!(email: attrs[:email]) do |u|
      u.first_name = attrs[:first_name]
      u.last_name  = attrs[:last_name]
      u.title      = attrs[:title]
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
  end

  puts "Seeded: #{Host.count} hosts, #{User.count} users, #{Event.count} events."
  puts "Log in with any seeded email — magic-link URL is printed to log/development.log."
end
