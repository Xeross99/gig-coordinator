# Seed sample data for development. Use `bin/rails db:seed`.
# Idempotent — running multiple times does not duplicate rows.

if Rails.env.development?
  host = Host.find_or_create_by!(email: "jan@example.com") do |h|
    h.first_name = "Jan"
    h.last_name  = "Kowalski"
    h.location   = "Słoneczna 12, 00-001 Warszawa"
  end

  anna = Host.find_or_create_by!(email: "anna@example.com") do |h|
    h.first_name = "Anna"
    h.last_name  = "Nowak"
    h.location   = "Polna 5, 30-001 Kraków"
  end

  [
    { first_name: "Michał",   last_name: "Kowalska",  email: "admin@gigcoordinator.pl",       title: :master, admin: true },
    { first_name: "Adam",     last_name: "Nowak",      email: "example1@gigcoordinator.pl",         title: :master },
    { first_name: "Michał",   last_name: "Wiśniewski",  email: "example2@gigcoordinator.pl",    title: :rookie },
    { first_name: "Marcin",   last_name: "Lewandowski",       email: "example3@gigcoordinator.pl",    title: :member },
    { first_name: "Mateusz",  last_name: "Zieliński",  email: "example4@gigcoordinator.pl",    title: :veteran },
    { first_name: "Ksawery",  last_name: "Szymański",     email: "example5@gigcoordinator.pl",    title: :member },
    { first_name: "Piotr",    last_name: "Dąbrowski",       email: "example6@gigcoordinator.pl",    title: :member }
  ].each do |attrs|
    user = User.find_or_create_by!(email: attrs[:email]) do |u|
      u.first_name = attrs[:first_name]
      u.last_name  = attrs[:last_name]
      u.title      = attrs[:title]
      u.admin      = attrs.fetch(:admin, false)
    end
    # Idempotent admin + title refresh: if the user already existed, realign the
    # flag/rank with seed intent (so ad-hoc changes from the console don't
    # persist across `db:seed` re-runs).
    desired_admin = attrs.fetch(:admin, false)
    user.update!(admin: desired_admin) if user.admin != desired_admin
    user.update!(title: attrs[:title])  if user.title.to_sym != attrs[:title]
  end

  unless host.events.exists?
    next_thursday = Date.current.next_occurring(:thursday)
    host.events.create!(
      name: "Kowalski 3 auta",
      scheduled_at: next_thursday.to_time.change(hour: 19, min: 0),
      ends_at:      next_thursday.to_time.change(hour: 22, min: 30),
      pay_per_person: 150.0,
      capacity: 4
    )
  end

  unless anna.events.exists?
    next_saturday = Date.current.next_occurring(:saturday)
    anna.events.create!(
      name: "Wydarzenie u Anny",
      scheduled_at: next_saturday.to_time.change(hour: 8, min: 0),
      ends_at:      next_saturday.to_time.change(hour: 11, min: 0),
      pay_per_person: 120.0,
      capacity: 3
    )
  end

  # Przykładowa blokada — Mateusz (weteran) zablokowany u Anny. Blokady
  # mistrzów są zabronione walidacją, więc demo robimy na niższej randze.
  mateusz = User.find_by(email: "example4@gigcoordinator.pl")
  HostBlock.find_or_create_by!(user: mateusz, host: anna) if mateusz

  puts "Seeded: #{Host.count} hosts, #{User.count} users, #{Event.count} events."
  puts "Log in with any seeded email — bin/login-code <email> prints a 5-digit code."
end
