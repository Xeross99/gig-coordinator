# Seed sample data for development. Use `bin/rails db:seed`.
# Idempotent — running multiple times does not duplicate rows.

if Rails.env.development?
  host = Host.find_or_create_by!(email: "jan@example.com") do |h|
    h.first_name = "Jan"
    h.last_name  = "Kurczyk"
    h.location   = "Pawia 112, 43-243 Wisła Mała"
  end

  anna = Host.find_or_create_by!(email: "anna@example.com") do |h|
    h.first_name = "Anna"
    h.last_name  = "Piórowska"
    h.location   = "Kwiatowa 7, 32-100 Proszowice"
  end

  [
    { first_name: "Anna",     last_name: "Kowalska",   email: "admin@example.com",     title: :mistrz_piora, admin: true },
    { first_name: "Adam",     last_name: "Nowak",      email: "example1@example.com",  title: :mistrz_piora, premium: true },
    { first_name: "Tomasz",   last_name: "Wiśniewski", email: "example2@example.com",  title: :zoltodziob },
    { first_name: "Marcin",   last_name: "Lewandowski",       email: "example3@example.com",    title: :kurzy_pacholek },
    { first_name: "Mateusz",  last_name: "Zieliński",  email: "example4@example.com",    title: :kurnikowy_gangster },
    { first_name: "Ksawery",  last_name: "Szymański",     email: "example5@example.com",    title: :kurzy_pacholek },
    { first_name: "Piotr",    last_name: "Dąbrowski",       email: "example6@example.com",    title: :kurzy_pacholek }
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
    desired_premium = attrs.fetch(:premium, false)
    user.update!(premium: desired_premium) if user.premium_active? != desired_premium
  end

  unless host.events.exists?
    next_thursday = Date.current.next_occurring(:thursday)
    host.events.create!(
      name: "Kurczyk 3 auta",
      scheduled_at: next_thursday.to_time.change(hour: 19, min: 0),
      ends_at:      next_thursday.to_time.change(hour: 22, min: 30),
      pay_per_person: 150.0,
      capacity: 4
    )
  end

  unless anna.events.exists?
    next_saturday = Date.current.next_occurring(:saturday)
    anna.events.create!(
      name: "Zlecenie kur u Anny",
      scheduled_at: next_saturday.to_time.change(hour: 8, min: 0),
      ends_at:      next_saturday.to_time.change(hour: 11, min: 0),
      pay_per_person: 120.0,
      capacity: 3
    )
  end

  # Przykładowa blokada — Mateusz (gangster) zablokowany u Anny. Blokady
  # mistrzów są zabronione walidacją, więc demo robimy na niższej randze.
  mateusz = User.find_by(email: "example4@example.com")
  HostBlock.find_or_create_by!(user: mateusz, host: anna) if mateusz

  # Przykładowa kampania z 2 sub-eventami — pokazuje primary roster + auto-zapis.
  unless host.event_campaigns.exists?
    creator = User.find_by(email: "admin@example.com")
    next_friday   = Date.current.next_occurring(:friday)
    next_next_fri = next_friday + 7.days
    campaign = host.event_campaigns.create!(
      name: "Marzec — kampania regularna",
      creator: creator,
      capacity: 4
    )
    campaign.events.create!(
      host: host,
      name: "Zlecenie 1 (kampania)",
      scheduled_at: next_friday.to_time.change(hour: 7, min: 0),
      ends_at:      next_friday.to_time.change(hour: 10, min: 0),
      pay_per_person: 150.0,
      capacity: 4
    )
    campaign.events.create!(
      host: host,
      name: "Zlecenie 2 (kampania)",
      scheduled_at: next_next_fri.to_time.change(hour: 7, min: 0),
      ends_at:      next_next_fri.to_time.change(hour: 10, min: 0),
      pay_per_person: 150.0,
      capacity: 4
    )
  end

  puts "Seeded: #{Host.count} hosts, #{User.count} users, #{Event.count} events, #{EventCampaign.count} campaigns."
  puts "Log in with any seeded email — bin/login-code <email> prints a 5-digit code."
end
