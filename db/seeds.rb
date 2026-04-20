# Seed sample data for development. Use `bin/rails db:seed`.
# Idempotent — running multiple times does not duplicate rows.

if Rails.env.development?
  host = Host.find_or_create_by!(email: "jan@example.com") do |h|
    h.first_name = "Jan"
    h.last_name  = "Kowalski"
    h.location   = "Słoneczna 12, 00-001 Warszawa"
  end

  [
    { first_name: "Michał",   last_name: "Kowalska",  email: "admin@gigcoordinator.pl",       title: :master },
    { first_name: "Adam",     last_name: "Nowak",      email: "example1@gigcoordinator.pl",         title: :master },
    { first_name: "Michał",   last_name: "Wiśniewski",  email: "example2@gigcoordinator.pl",    title: :rookie },
    { first_name: "Marcin",   last_name: "Lewandowski",       email: "example3@gigcoordinator.pl",    title: :member },
    { first_name: "Mateusz",  last_name: "Zieliński",  email: "example4@gigcoordinator.pl",    title: :veteran },
    { first_name: "Ksawery",  last_name: "Szymański",     email: "example5@gigcoordinator.pl",    title: :member },
    { first_name: "Piotr",    last_name: "Dąbrowski",       email: "example6@gigcoordinator.pl",    title: :member }
  ].each do |attrs|
    User.find_or_create_by!(email: attrs[:email]) do |u|
      u.first_name = attrs[:first_name]
      u.last_name  = attrs[:last_name]
      u.title      = attrs[:title]
    end
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

  puts "Seeded: #{Host.count} hosts, #{User.count} users, #{Event.count} events."
  puts "Log in with any seeded email — bin/login-code <email> prints a 5-digit code."
end
