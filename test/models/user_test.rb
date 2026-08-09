require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "newly built user has admin=false by default" do
    assert_equal false, User.new.admin
  end

  test "persisting without admin defaults to false" do
    u = User.create!(first_name: "T", last_name: "T", email: "t@t.pl")
    assert_equal false, u.reload.admin
  end

  test "valid user can be created" do
    user = User.new(first_name: "Zofia", last_name: "Kwiatkowska", email: "zofia@example.com")
    assert user.valid?, user.errors.full_messages.inspect
  end

  test "requires first_name, last_name, email" do
    user = User.new
    refute user.valid?
    assert user.errors[:first_name].any?
    assert user.errors[:last_name].any?
    assert user.errors[:email].any?
  end

  test "email is unique case-insensitively" do
    User.create!(first_name: "A", last_name: "B", email: "u1@example.com")
    dup = User.new(first_name: "C", last_name: "D", email: "U1@EXAMPLE.COM")
    refute dup.valid?
    assert dup.errors.of_kind?(:email, :taken)
  end

  test "first_name+last_name pair is unique" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "first@example.com")
    dup = User.new(first_name: "Adam", last_name: "Nowak", email: "second@example.com")
    refute dup.valid?
    assert dup.errors.of_kind?(:first_name, :taken)
  end

  test "first_name uniqueness is case-insensitive within the same last_name" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "first2@example.com")
    dup = User.new(first_name: "ADAM", last_name: "Nowak", email: "second2@example.com")
    refute dup.valid?
    assert dup.errors.of_kind?(:first_name, :taken)
  end

  test "same first_name with different last_name is allowed" do
    User.create!(first_name: "Anna", last_name: "Kowalska", email: "a1@example.com")
    other = User.new(first_name: "Anna", last_name: "Wiśniewska", email: "a2@example.com")
    assert other.valid?, other.errors.full_messages.inspect
  end

  test "same last_name with different first_name is allowed" do
    User.create!(first_name: "Adam", last_name: "Nowak", email: "b1@example.com")
    other = User.new(first_name: "Piotr", last_name: "Nowak", email: "b2@example.com")
    assert other.valid?, other.errors.full_messages.inspect
  end

  test "email normalized" do
    user = User.create!(first_name: "A", last_name: "B", email: "  UPPER@X.COM ")
    assert_equal "upper@x.com", user.email
  end

  test "email format is validated" do
    user = User.new(first_name: "A", last_name: "B", email: "not-an-email")
    refute user.valid?
    assert user.errors.of_kind?(:email, :invalid)
  end

  test "updating own record does not conflict with itself on name uniqueness" do
    user = User.create!(first_name: "Self", last_name: "Update", email: "self@example.com")
    user.first_name = "Self"
    user.last_name  = "Update"
    assert user.valid?, user.errors.full_messages.inspect
  end

  test "has_many participations and push_subscriptions" do
    assert User.reflect_on_association(:participations)
    assert User.reflect_on_association(:push_subscriptions)
  end

  test "has :photo attachment with :small variant declared" do
    reflection = User.reflect_on_attachment(:photo)
    assert reflection, ":photo attachment should be defined via Avatarable"
    assert reflection.named_variants.key?(:small), ":small variant should be declared"
  end

  test ":photo can resolve the :small variant on an attached blob" do
    user = users(:ala)
    user.photo.attach(io: StringIO.new("fake"), filename: "avatar.png", content_type: "image/png")
    assert user.photo.attached?
    assert_nothing_raised { user.photo.variant(:small) }
  end

  test "title defaults to zoltodziob (0)" do
    user = User.create!(first_name: "A", last_name: "B", email: "fresh@example.com")
    assert_equal "zoltodziob", user.title
  end

  test "title enum exposes all five ranks" do
    assert_equal %w[zoltodziob kurzy_pacholek kurnikowy_gangster kurnikowy_komendant mistrz_piora], User.titles.keys
  end

  test "display_title returns the i18n-translated label" do
    user = User.new(title: :mistrz_piora)
    assert_equal User::TITLE_LABELS["mistrz_piora"], user.display_title
    assert_equal "Mistrz Pióra", user.display_title
  end

  test "title_badge_classes returns tier color" do
    assert_equal "bg-gray-100 text-gray-600",     User.new(title: :zoltodziob).title_badge_classes
    assert_equal "bg-green-100 text-green-700",   User.new(title: :kurzy_pacholek).title_badge_classes
    assert_equal "bg-blue-100 text-blue-700",     User.new(title: :kurnikowy_gangster).title_badge_classes
    assert_equal "bg-purple-100 text-purple-700", User.new(title: :kurnikowy_komendant).title_badge_classes
    assert_equal "bg-yellow-100 text-yellow-800", User.new(title: :mistrz_piora).title_badge_classes
  end

  test "online? is true within ONLINE_WINDOW and false outside" do
    user = users(:ala)
    user.update_column(:last_seen_at, 2.minutes.ago)
    assert user.online?

    user.update_column(:last_seen_at, 10.minutes.ago)
    refute user.online?
  end

  test "online? is false when last_seen_at is nil" do
    user = users(:ala)
    user.update_column(:last_seen_at, nil)
    refute user.online?
  end

  test "welcome email is enqueued on create" do
    assert_enqueued_emails 1 do
      User.create!(first_name: "Nowy", last_name: "User", email: "nowy@example.com")
    end
  end

  test "welcome email is NOT enqueued on update" do
    user = User.create!(first_name: "Up", last_name: "Date", email: "upd@example.com")
    assert_enqueued_emails 0 do
      user.update!(first_name: "Zmieniony")
    end
  end

  test "rank promotion email is enqueued on awans to mistrz_piora" do
    user = users(:ala)
    user.update!(title: :kurzy_pacholek)
    assert_enqueued_emails 1 do
      user.update!(title: :mistrz_piora)
    end
  end

  test "rank promotion email is enqueued on awans to kurnikowy_komendant" do
    user = users(:ala)
    user.update!(title: :kurzy_pacholek)
    assert_enqueued_emails 1 do
      user.update!(title: :kurnikowy_komendant)
    end
  end

  test "rank promotion email is enqueued on awans to lower ranks (kurzy_pacholek, gangster)" do
    %i[kurzy_pacholek kurnikowy_gangster].each do |target|
      user = User.create!(first_name: "Awans#{target}", last_name: "Lower",
                          email: "awans_#{target}@example.com") # default zoltodziob
      enqueued_before = enqueued_jobs.count { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" }
      user.update!(title: target)
      enqueued_after  = enqueued_jobs.count { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" }
      assert_equal 1, enqueued_after - enqueued_before,
        "awans zoltodziob → #{target} musi wysłać dokładnie 1 mail"
    end
  end

  test "rank promotion mail is NOT enqueued on the very first title assignment" do
    # Pierwszy create ustawia title — `after_update_commit` w ogóle się nie odpala
    # na create, więc nie ma ryzyka „gratulujemy świeżakowi awansu na startową rangę".
    enqueued_before = enqueued_jobs.count { |j|
      j["job_class"] == "ActionMailer::MailDeliveryJob" &&
      ActiveJob::Arguments.deserialize(j["arguments"]).first == "RankPromotionMailer"
    }
    User.create!(first_name: "First", last_name: "Title",
                 email: "first_title@example.com", title: :kurnikowy_komendant)
    enqueued_after = enqueued_jobs.count { |j|
      j["job_class"] == "ActionMailer::MailDeliveryJob" &&
      ActiveJob::Arguments.deserialize(j["arguments"]).first == "RankPromotionMailer"
    }
    assert_equal 0, enqueued_after - enqueued_before,
      "create nie powinien wysyłać RankPromotionMailera (welcome mail to inny mailer i jest OK)"
  end

  test "rank promotion email is NOT enqueued for a degradation" do
    user = users(:ala)
    user.update!(title: :mistrz_piora)
    assert_enqueued_emails 0 do
      user.update!(title: :kurnikowy_gangster)
    end
  end

  test "rank promotion email is NOT enqueued when title changes to a low rank" do
    user = users(:ala)
    user.update!(title: :mistrz_piora)
    assert_enqueued_emails 0 do
      user.update!(title: :kurzy_pacholek)
    end
  end

  test "rank promotion email is NOT enqueued on non-title updates" do
    user = users(:ala)
    user.update!(title: :mistrz_piora)
    assert_enqueued_emails 0 do
      user.update!(first_name: "Inne")
    end
  end

  test "rank promotion email is NOT enqueued when user has no email" do
    user = users(:ala)
    user.update!(title: :kurzy_pacholek)
    User.connection.execute("UPDATE users SET email = '' WHERE id = #{user.id}")
    user.reload
    assert user.email.blank?, "email should be blank for this test"
    user.title = :mistrz_piora
    assert_enqueued_emails 0 do
      user.save(validate: false)
    end
  end

  test "display_title returns the i18n-translated label for kurnikowy_komendant" do
    user = User.new(title: :kurnikowy_komendant)
    assert_equal "Kurnikowy Komendant", user.display_title
  end

  test "mistrz_piora maps to DB value 4 after renumber" do
    assert_equal 4, User.titles["mistrz_piora"]
    assert_equal 3, User.titles["kurnikowy_komendant"]
  end

  test "managed_hosts returns hosts via host_managers join" do
    user = users(:ala)
    user.managed_hosts << hosts(:jan)
    user.managed_hosts << hosts(:anna)
    assert_equal 2, user.managed_hosts.count
    assert_includes user.managed_hosts, hosts(:jan)
    assert_includes user.managed_hosts, hosts(:anna)
  end

  test "can_create_events? is true for mistrz_piora even without managed_hosts" do
    user = users(:ala)
    user.update!(title: :mistrz_piora)
    assert user.can_create_events?
  end

  test "can_create_events? is true for kurnikowy_komendant with at least one managed_host" do
    user = users(:ala)
    user.update!(title: :kurnikowy_komendant)
    user.managed_hosts << hosts(:jan)
    assert user.can_create_events?
  end

  test "can_create_events? is false for kurnikowy_komendant without managed_hosts" do
    user = users(:ala)
    user.update!(title: :kurnikowy_komendant)
    refute user.can_create_events?
  end

  test "can_create_events? is false for lower ranks regardless of managed_hosts" do
    user = users(:ala)
    user.managed_hosts << hosts(:jan)
    %i[zoltodziob kurzy_pacholek kurnikowy_gangster].each do |title|
      user.update!(title: title)
      refute user.can_create_events?, "#{title} powinien NIE móc tworzyć eventów"
    end
  end

  test "event_creator_rank? is true for mistrz_piora" do
    users(:ala).update!(title: :mistrz_piora)
    assert users(:ala).event_creator_rank?
  end

  test "can_join_events? is false ONLY for zoltodziob" do
    user = users(:ala)
    user.update!(title: :zoltodziob)
    refute user.can_join_events?, "zoltodziob to obserwator — nie zapisuje się"

    %i[kurzy_pacholek kurnikowy_gangster kurnikowy_komendant mistrz_piora].each do |title|
      user.update!(title: title)
      assert user.can_join_events?, "#{title} powinien móc się zapisywać"
    end
  end

  test "event_creator_rank? is true for kurnikowy_komendant regardless of managed_hosts" do
    users(:ala).update!(title: :kurnikowy_komendant)
    assert users(:ala).event_creator_rank?
  end

  test "event_creator_rank? is false for lower ranks" do
    %i[zoltodziob kurzy_pacholek kurnikowy_gangster].each do |title|
      users(:ala).update!(title: title)
      refute users(:ala).event_creator_rank?, "#{title} nie powinien mieć rangi planisty"
    end
  end

  test "phone is optional" do
    user = User.new(first_name: "Bez", last_name: "Tel", email: "beztel@example.com")
    assert user.valid?, user.errors.full_messages.inspect
    assert_nil user.phone
  end

  test "phone is stripped of surrounding whitespace" do
    user = User.create!(first_name: "Z", last_name: "Tel", email: "ztel@example.com", phone: "  +48 123 456 789  ")
    assert_equal "+48 123 456 789", user.phone
  end

  test "blank phone is normalized to nil" do
    user = User.create!(first_name: "Pusty", last_name: "Tel", email: "pusty@example.com", phone: "   ")
    assert_nil user.phone
  end

  # --- premium + karty gracza ---------------------------------------------------

  test "player_card musi być jedną ze zdefiniowanych kart" do
    user = users(:bartek)
    user.update!(premium: true)

    assert user.update(player_card: "traktor")
    refute user.update(player_card: "nieistniejaca"), "nieznana karta powinna być odrzucona"
  end

  test "pusty player_card normalizuje się do nil" do
    user = users(:bartek)
    user.update!(premium: true, player_card: "traktor")
    user.update!(player_card: "")
    assert_nil user.reload.player_card
  end

  test "odebranie premium czyści wybraną kartę przy zapisie" do
    user = users(:bartek)
    user.update!(premium: true, player_card: "kontener")

    user.update!(premium: false)

    assert_nil user.reload.player_card
  end

  test "player_card ustawiony bez premium jest zerowany przy zapisie" do
    user = users(:bartek)
    user.update!(player_card: "kontener")
    assert_nil user.reload.player_card
  end

  test "admin ma premium niezależnie od premium_until" do
    user = users(:ala) # admin: true w fixturze
    assert_nil user.premium_until
    assert user.premium?
    # skoro premium? = true, karta nie jest czyszczona przy zapisie
    user.update!(player_card: "ladowarka")
    assert_equal "ladowarka", user.reload.player_card
  end

  test "player_card? tylko gdy premium i karta wybrana" do
    user = users(:bartek)
    refute user.player_card?

    user.update!(premium: true)
    refute user.player_card?, "premium bez wybranej karty"

    user.update!(player_card: "kosmos")
    assert user.player_card?
  end

  test "nadanie premium wysyła push z podziękowaniem" do
    user = users(:bartek)

    assert_enqueued_with(job: WebPushNotifier, args: [ :premium_granted, { user_id: user.id } ]) do
      user.update!(premium: true)
    end
  end

  test "ponowny zapis bez zmiany premium i odebranie premium nie wysyłają pusha" do
    user = users(:bartek)
    user.update!(premium: true)

    assert_no_enqueued_jobs(only: WebPushNotifier) do
      user.update!(premium: true) # checkbox bez zmiany stanu
      user.update!(premium: false)
    end
  end

  test "premium= nadaje rok i nie przedłuża przy ponownym zapisie" do
    user = users(:bartek)
    user.update!(premium: true)
    first_deadline = user.reload.premium_until
    assert_in_delta User::PREMIUM_DURATION.from_now.to_f, first_deadline.to_f, 5

    travel 1.day do
      user.update!(premium: true) # checkbox bez zmiany stanu
      assert_equal first_deadline, user.reload.premium_until

      user.update!(premium: false)
      assert_nil user.reload.premium_until
    end
  end

  test "wygasłe premium wyłącza kartę gracza" do
    user = users(:bartek)
    user.update!(premium: true, player_card: "traktor")
    assert user.player_card?

    user.update_column(:premium_until, 1.hour.ago) # wygasa bez zapisu modelu
    refute user.reload.premium?
    refute user.player_card?
    # najbliższy zapis czyści kolumnę
    user.update!(phone: "123 456 789")
    assert_nil user.reload.player_card
  end

  test "PLAYER_CARDS mają pliki SVG i etykiety" do
    User::PLAYER_CARDS.each do |card|
      path = Rails.root.join("app/assets/images/player_cards/#{card}.svg")
      assert File.exist?(path), "brak pliku #{path}"
      assert User::PLAYER_CARD_LABELS[card].present?, "brak etykiety dla karty #{card}"
    end
  end
end
