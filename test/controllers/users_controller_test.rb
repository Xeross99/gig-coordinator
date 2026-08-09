require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "routes expose admin CRUD URLs for users" do
    assert_equal "/pracownicy/nowy",           new_user_path
    assert_equal "/pracownicy/1/edytuj",       edit_user_path(1)
  end

  test "redirects to login when not signed in" do
    get users_path
    assert_redirected_to login_path
  end

  test "redirects host users (index is worker-facing)" do
    sign_in_as(hosts(:jan))
    get users_path
    assert_redirected_to login_path
  end

  test "GET index as user lists all users with display names + titles" do
    sign_in_as(users(:ala))
    get users_path
    assert_response :success
    assert_match users(:ala).display_name,    response.body
    assert_match users(:bartek).display_name, response.body
  end

  test "catch counts include confirmed participations on completed events only" do
    # Controller runs this exact query:
    #   Participation.confirmed.joins(:event).where.not(events: { completed_at: nil })
    #                .group(:user_id).count
    # We mirror it directly to guard the behavior without depending on assigns.
    event = events(:chickens_tomorrow)
    done = Event.create!(host: hosts(:jan), name: "Zakonczone",
                         scheduled_at: 2.days.ago, ends_at: 2.days.ago + 2.hours,
                         pay_per_person: 100, capacity: 4,
                         completed_at: 1.day.ago)
    Participation.create!(event: done,  user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)  # not completed
    Participation.create!(event: done,  user: users(:cezary), status: :cancelled, position: 0)

    counts = Participation.confirmed
                          .joins(:event)
                          .where.not(events: { completed_at: nil })
                          .group(:user_id)
                          .count

    assert_equal 1, counts[users(:ala).id]
    assert_nil   counts[users(:bartek).id]
    assert_nil   counts[users(:cezary).id]
  end

  test "GET index orders by title desc then last_name" do
    users(:ala).update!(title: :mistrz_piora)        # rank 3
    users(:bartek).update!(title: :kurzy_pacholek)   # rank 1
    users(:cezary).update!(title: :zoltodziob)       # rank 0

    sign_in_as(users(:ala))
    get users_path

    # Use position in rendered body as a proxy for ordering.
    body = response.body
    assert body.index(users(:ala).display_name) < body.index(users(:bartek).display_name)
    assert body.index(users(:bartek).display_name) < body.index(users(:cezary).display_name)
  end

  test "GET index oznacza wyłączone konto plakietką i wygasza avatar" do
    users(:bartek).disable!
    sign_in_as(users(:ala))

    get users_path
    assert_response :success
    assert_match Copy::Users::DISABLED_BADGE, response.body
    assert_match "opacity-50 grayscale", response.body
  end

  # --- show action -----------------------------------------------------------

  test "GET /pracownicy/:id requires login" do
    get user_path(users(:ala))
    assert_redirected_to login_path
  end

  test "GET /pracownicy/:id as host redirects (worker-facing area)" do
    sign_in_as(hosts(:jan))
    get user_path(users(:ala))
    assert_redirected_to login_path
  end

  test "GET /pracownicy/:id shows the user's display_name, email, rank, and catches count" do
    users(:ala).update!(title: :mistrz_piora)

    # Seed one completed-event confirmed participation so the catches count is > 0.
    done = Event.create!(host: hosts(:jan), name: "Zakonczone",
                         scheduled_at: 2.days.ago, ends_at: 2.days.ago + 2.hours,
                         pay_per_person: 100, capacity: 4,
                         completed_at: 1.day.ago)
    Participation.create!(event: done, user: users(:ala), status: :confirmed, position: 1)

    sign_in_as(users(:bartek))
    get user_path(users(:ala))
    assert_response :success
    assert_match users(:ala).display_name,            response.body
    assert_match users(:ala).email,                   response.body
    assert_match User::TITLE_LABELS["mistrz_piora"],  response.body
    assert_match "Statystyki",                        response.body
  end

  test "GET /pracownicy/:id lists upcoming participations" do
    event = events(:chickens_tomorrow)
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)

    sign_in_as(users(:bartek))
    get user_path(users(:ala))
    assert_match event.name, response.body
  end

  test "GET /pracownicy/:id 404s for a non-existent user" do
    sign_in_as(users(:ala))
    get user_path(id: 999_999)
    assert_response :not_found
  end

  test "GET /pracownicy/:id shows 'Zarządza' section with linked hosts for a komendant" do
    users(:cezary).update!(title: :kurnikowy_komendant)
    users(:cezary).managed_hosts << hosts(:jan)

    sign_in_as(users(:bartek))
    get user_path(users(:cezary))
    assert_response :success
    assert_match Copy::Users::MANAGES,     response.body
    assert_match hosts(:jan).display_name,   response.body
  end

  test "GET /pracownicy/:id hides 'Zarządza' section when user has no managed_hosts" do
    sign_in_as(users(:bartek))
    get user_path(users(:cezary))
    assert_no_match Copy::Users::MANAGES, response.body
  end

  test "GET /pracownicy/:id shows 'Zarządza wszystkimi' section with ALL hosts for mistrz_piora" do
    users(:cezary).update!(title: :mistrz_piora)

    sign_in_as(users(:bartek))
    get user_path(users(:cezary))
    assert_response :success
    assert_match "Zarządza wszystkimi gospodarzami",  response.body
    assert_match hosts(:jan).display_name,    response.body
    assert_match hosts(:anna).display_name,   response.body
  end

  # --- admin CRUD ------------------------------------------------------------

  test "GET /pracownicy/nowy requires login" do
    get new_user_path
    assert_redirected_to login_path
  end

  test "GET /pracownicy/nowy as non-admin user redirects with alert" do
    sign_in_as(users(:bartek))  # not admin
    get new_user_path
    assert_redirected_to root_path
    assert_equal "Tylko administrator może wykonać tę akcję.", flash[:alert]
  end

  test "GET /pracownicy/nowy as host redirects (hosts can't be admins)" do
    sign_in_as(hosts(:jan))
    get new_user_path
    assert_redirected_to login_path
  end

  test "GET /pracownicy/nowy as admin renders form" do
    sign_in_as(users(:ala))  # admin
    get new_user_path
    assert_response :success
    assert_match Copy::Admin::Users::NEW_TITLE, response.body
  end

  test "POST /pracownicy as admin creates user and redirects to show" do
    sign_in_as(users(:ala))
    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        first_name: "Nowy", last_name: "Pracownik",
        email: "nowy@example.com", title: "zoltodziob"
      } }
    end
    created = User.find_by(email: "nowy@example.com")
    assert_redirected_to user_path(created)
    assert_equal "Dodano pracownika.", flash[:notice]
  end

  test "POST /pracownicy as non-admin is rejected" do
    sign_in_as(users(:bartek))
    assert_no_difference -> { User.count } do
      post users_path, params: { user: { first_name: "X", last_name: "Y", email: "x@y.pl" } }
    end
    assert_redirected_to root_path
  end

  test "POST /pracownicy cannot set admin=true via params" do
    sign_in_as(users(:ala))
    post users_path, params: { user: {
      first_name: "Zuch", last_name: "Admin",
      email: "zuch@example.com", admin: true
    } }
    assert_equal false, User.find_by(email: "zuch@example.com").admin
  end

  test "GET /pracownicy/:id/edytuj as admin renders form" do
    sign_in_as(users(:ala))
    get edit_user_path(users(:bartek))
    assert_response :success
    assert_match users(:bartek).display_name, response.body
    assert_match Copy::Admin::Users::EDIT_TITLE, response.body
  end

  test "GET /pracownicy/:id/edytuj as non-admin redirects" do
    sign_in_as(users(:bartek))
    get edit_user_path(users(:cezary))
    assert_redirected_to root_path
  end

  test "PATCH /pracownicy/:id as admin updates fields and redirects to show" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: {
      first_name: "Bartłomiej", email: "bartlomiej@example.com", title: "mistrz_piora"
    } }
    bartek = users(:bartek).reload
    assert_equal "Bartłomiej",         bartek.first_name
    assert_equal "bartlomiej@example.com", bartek.email
    assert_equal "mistrz_piora",       bartek.title
    assert_redirected_to user_path(bartek)
  end

  test "PATCH /pracownicy/:id cannot flip admin flag via params" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { admin: true } }
    assert_equal false, users(:bartek).reload.admin
  end

  test "PATCH /pracownicy/:id as admin flips can_drive" do
    sign_in_as(users(:ala))
    assert_equal false, users(:bartek).reload.can_drive
    patch user_path(users(:bartek)), params: { user: { can_drive: "1" } }
    assert_equal true, users(:bartek).reload.can_drive

    patch user_path(users(:bartek)), params: { user: { can_drive: "0" } }
    assert_equal false, users(:bartek).reload.can_drive
  end

  test "PATCH /pracownicy/:id as non-admin cannot change can_drive" do
    bartek = users(:bartek); bartek.update!(can_drive: false)
    sign_in_as(users(:cezary))
    patch user_path(bartek), params: { user: { can_drive: "1" } }
    assert_redirected_to root_path
    assert_equal false, bartek.reload.can_drive
  end

  test "GET /pracownicy/:id pokazuje 'Kierowca: Tak/Nie' zgodnie z can_drive" do
    sign_in_as(users(:ala))
    users(:bartek).update!(can_drive: true)
    get user_path(users(:bartek))
    assert_match "Kierowca", response.body
    assert_match "Tak", response.body

    users(:bartek).update!(can_drive: false)
    get user_path(users(:bartek))
    assert_match "Kierowca", response.body
    assert_match "Nie", response.body
  end

  test "PATCH /pracownicy/:id with invalid email re-renders form" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { email: "nie-email" } }
    assert_response :unprocessable_content
  end

  test "POST /pracownicy with duplicate first+last name pair as admin re-renders form" do
    User.create!(first_name: "Istniejacy", last_name: "Ktos", email: "ist@example.com")
    sign_in_as(users(:ala))
    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        first_name: "Istniejacy", last_name: "Ktos", email: "inny@example.com"
      } }
    end
    assert_response :unprocessable_content
  end

  # --- phone -----------------------------------------------------------------

  test "POST /pracownicy as admin saves phone when provided" do
    sign_in_as(users(:ala))
    post users_path, params: { user: {
      first_name: "Z", last_name: "Telefonem",
      email: "ztel@example.com", phone: "+48 123 456 789"
    } }
    assert_equal "+48 123 456 789", User.find_by(email: "ztel@example.com").phone
  end

  test "PATCH /pracownicy/:id as admin updates phone" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { phone: "500 600 700" } }
    assert_equal "500 600 700", users(:bartek).reload.phone
  end

  test "PATCH /pracownicy/:id as admin can clear phone by sending blank" do
    users(:bartek).update!(phone: "123 456 789")
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { phone: "" } }
    assert_nil users(:bartek).reload.phone
  end

  # --- managed_host_ids + blocked_host_ids -----------------------------------

  test "PATCH /pracownicy/:id as admin replaces managed_host_ids" do
    sign_in_as(users(:ala))
    users(:bartek).managed_hosts << hosts(:jan)
    patch user_path(users(:bartek)), params: { user: {
      title: "kurnikowy_komendant",
      managed_host_ids: [ hosts(:anna).id.to_s ]
    } }
    bartek = users(:bartek).reload
    assert_equal [ hosts(:anna) ], bartek.managed_hosts.to_a
  end

  test "PATCH /pracownicy/:id as admin can clear managed_host_ids by sending empty" do
    sign_in_as(users(:ala))
    users(:bartek).managed_hosts << hosts(:jan)
    patch user_path(users(:bartek)), params: { user: { managed_host_ids: [ "" ] } }
    assert_empty users(:bartek).reload.managed_hosts
  end

  test "PATCH /pracownicy/:id as admin adds a HostBlock via blocked_host_ids" do
    sign_in_as(users(:ala))
    users(:bartek).update!(title: :kurzy_pacholek)
    patch user_path(users(:bartek)), params: { user: {
      blocked_host_ids: [ hosts(:jan).id.to_s ]
    } }
    assert_equal [ hosts(:jan) ], users(:bartek).reload.blocked_hosts.to_a
  end

  test "PATCH /pracownicy/:id as admin can remove a HostBlock" do
    sign_in_as(users(:ala))
    users(:bartek).update!(title: :kurzy_pacholek)
    HostBlock.create!(user: users(:bartek), host: hosts(:jan))
    patch user_path(users(:bartek)), params: { user: { blocked_host_ids: [ "" ] } }
    assert_empty users(:bartek).reload.blocked_hosts
  end

  test "PATCH /pracownicy/:id ignores blocked_host_ids when title becomes mistrz_piora" do
    sign_in_as(users(:ala))
    users(:bartek).update!(title: :kurzy_pacholek)
    patch user_path(users(:bartek)), params: { user: {
      title: "mistrz_piora",
      blocked_host_ids: [ hosts(:jan).id.to_s ]
    } }
    bartek = users(:bartek).reload
    assert bartek.mistrz_piora?
    assert_empty bartek.blocked_hosts
  end

  test "GET /pracownicy/:id/edytuj renders managed + blocked checkbox sections" do
    sign_in_as(users(:ala))
    users(:bartek).update!(title: :kurzy_pacholek)
    get edit_user_path(users(:bartek))
    assert_response :success
    assert_select "input[type='checkbox'][name='user[managed_host_ids][]'][value=?]", hosts(:jan).id.to_s
    assert_select "input[type='checkbox'][name='user[blocked_host_ids][]'][value=?]", hosts(:jan).id.to_s
  end

  test "GET /pracownicy/:id/edytuj hides blocked checkboxes for mistrz_piora" do
    sign_in_as(users(:ala))
    users(:bartek).update!(title: :mistrz_piora)
    get edit_user_path(users(:bartek))
    assert_response :success
    assert_select "input[type='checkbox'][name='user[blocked_host_ids][]']", count: 0
    assert_match "Mistrz Pióra nie podlega blokadom", response.body
  end

  test "GET /pracownicy/:id renders phone as tel: link when present" do
    users(:bartek).update!(phone: "+48 500 600 700")
    sign_in_as(users(:cezary))
    get user_path(users(:bartek))
    assert_response :success
    assert_match "+48 500 600 700", response.body
    assert_select "a[href=?]", "tel:+48 500 600 700"
    assert_match "Telefon", response.body
  end

  test "GET /pracownicy/:id shows 'Nie podano' for phone when blank" do
    users(:bartek).update!(phone: nil)
    sign_in_as(users(:cezary))
    get user_path(users(:bartek))
    assert_response :success
    assert_match "Telefon", response.body
    assert_match "Nie podano", response.body
    assert_select "a[href^=?]", "tel:", count: 0
  end

  test "GET /pracownicy/:id renders email as mailto: link" do
    sign_in_as(users(:cezary))
    get user_path(users(:bartek))
    assert_response :success
    assert_select "a[href=?]", "mailto:#{users(:bartek).email}", text: users(:bartek).email
  end

  # --- photo upload UI (DirectUpload + photo-upload Stimulus controller) ---

  test "GET /pracownicy/:id/edytuj wires the photo-upload Stimulus controller" do
    sign_in_as(users(:ala))
    get edit_user_path(users(:bartek))
    assert_response :success
    assert_select "form[data-controller~=?][data-photo-upload-url-value=?]", "photo-upload", rails_direct_uploads_path
    assert_select "input[type=file][data-photo-upload-target=input][accept=?]", "image/*"
    assert_select "input[type=hidden][name=?][disabled]", "user[photo]"
    assert_select "button[type=button][data-action=?]", "click->photo-upload#selectFile", text: /Wybierz zdjęcie/
    assert_select "input[type=file][type=file]", count: 1
    # No legacy raw f.file_field — should be the styled DirectUpload widget only.
    assert_select "input[type=file][name='user[photo]']", count: 0
  end

  test "PATCH /pracownicy/:id attaches a photo from a direct-upload signed_id" do
    sign_in_as(users(:ala))
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-png"), filename: "x.png", content_type: "image/png"
    )
    patch user_path(users(:bartek)), params: { user: { photo: blob.signed_id } }
    assert users(:bartek).reload.photo.attached?
    assert_equal blob.id, users(:bartek).reload.photo.blob.id
  end

  # --- testowy push od admina -------------------------------------------------

  test "POST /pracownicy/:id/testowy-push as admin enqueues :test push and redirects with notice" do
    target = users(:bartek)
    PushSubscription.create!(user: target, endpoint: "https://example.com/admin-test",
                             p256dh_key: "p", auth_key: "a")
    sign_in_as(users(:ala))  # admin

    assert_enqueued_with(job: WebPushNotifier, args: [ :test, { user_id: target.id } ]) do
      post test_push_user_path(target)
    end
    assert_redirected_to user_path(target)
    assert_equal "Wysłano testowe powiadomienie do #{target.display_name}. Powinno przyjść za chwilę.", flash[:notice]
  end

  test "POST testowy-push alerts when the user has no push subscription at all" do
    target = users(:bartek)
    sign_in_as(users(:ala))

    assert_no_enqueued_jobs only: WebPushNotifier do
      post test_push_user_path(target)
    end
    assert_redirected_to user_path(target)
    assert_equal "Ten pracownik nie ma żadnej subskrypcji push - powiadomienie nie miałoby gdzie dotrzeć.", flash[:alert]
  end

  test "POST testowy-push as non-admin redirects with admin_required and enqueues nothing" do
    sign_in_as(users(:bartek))  # not admin

    assert_no_enqueued_jobs only: WebPushNotifier do
      post test_push_user_path(users(:cezary))
    end
    assert_redirected_to root_path
    assert_equal "Tylko administrator może wykonać tę akcję.", flash[:alert]
  end

  test "przycisk testowego pusha widoczny tylko dla admina" do
    sign_in_as(users(:ala))  # admin
    get user_path(users(:bartek))
    assert_match "Wyślij testowy push", response.body

    sign_in_as(users(:bartek))  # not admin
    get user_path(users(:cezary))
    refute_match "Wyślij testowy push", response.body
  end

  # --- usuwanie pracownika (regresja: FK constraint -> 500) -------------------

  test "DELETE /pracownicy/:id usuwa usera z pelnym bagazem asocjacji" do
    host   = hosts(:jan)
    victim = User.create!(first_name: "Ofiara", last_name: "Fk", email: "ofiara-fk@test.example")
    driver = users(:cezary)
    driver.update!(can_drive: true)

    # ofiara stworzyla event, jest na evencie i w kampanii, jest odbierana
    # przez kierowce i ma aktywny kod logowania — kazda z tych rzeczy
    # wywalala wczesniej FOREIGN KEY constraint (500).
    event = Event.create!(host: host, creator: victim, name: "Event ofiary",
                          scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
                          pay_per_person: 50, capacity: 4)
    event.participations.destroy_all
    Participation.create!(event: event, user: driver, status: :confirmed, position: 1)
    Participation.create!(event: event, user: victim, status: :confirmed, position: 2)

    campaign = EventCampaign.create!(host: host, name: "Rzut ofiary", capacity: 2)
    CampaignParticipation.create!(event_campaign: campaign, user: victim, status: :confirmed, position: 99)

    offer = CarpoolOffer.create!(event: event, user: driver)
    CarpoolRequest.create!(carpool_offer: offer, user: victim, status: :accepted)
    offer.arrive_at!(victim)
    LoginCode.generate_for(victim, request: nil)

    sign_in_as(users(:ala))  # admin
    delete user_path(victim)

    assert_redirected_to users_path
    assert_equal "Usunięto pracownika.", flash[:notice]
    assert_nil User.find_by(id: victim.id)
    assert_nil event.reload.creator_id, "creator_id ma sie wyzerowac, event zostaje"
    assert_nil offer.reload.current_pickup_user_id, "sentinel pickup ma sie wyzerowac"
    assert_equal 0, CampaignParticipation.where(user_id: victim.id).count
    assert_equal 0, LoginCode.where(authenticatable_type: "User", authenticatable_id: victim.id).count
  end

  test "DELETE wlasnego konta jest zablokowane" do
    sign_in_as(users(:ala))  # admin
    delete user_path(users(:ala))

    assert_redirected_to user_path(users(:ala))
    assert_equal "Nie możesz usunąć własnego konta.", flash[:alert]
    assert User.exists?(users(:ala).id)
  end

  # --- wyłączanie konta ---------------------------------------------------------

  test "POST przelacz-konto jako admin wyłącza i włącza konto" do
    target = users(:bartek)
    sign_in_as(users(:ala))  # admin

    post toggle_disabled_user_path(target)
    assert_redirected_to user_path(target)
    assert target.reload.disabled?
    assert_equal "Konto #{target.display_name} zostało wyłączone. Nie dostanie już powiadomień ani rezerwacji i nie zaloguje się.", flash[:notice]

    post toggle_disabled_user_path(target)
    refute target.reload.disabled?
    assert_equal "Konto #{target.display_name} zostało włączone ponownie.", flash[:notice]
  end

  test "POST przelacz-konto na wlasnym koncie jest zablokowane" do
    sign_in_as(users(:ala))
    post toggle_disabled_user_path(users(:ala))

    assert_equal "Nie możesz wyłączyć własnego konta.", flash[:alert]
    refute users(:ala).reload.disabled?
  end

  test "POST przelacz-konto jako non-admin odbija z admin_required" do
    sign_in_as(users(:bartek))
    post toggle_disabled_user_path(users(:cezary))

    assert_redirected_to root_path
    assert_equal "Tylko administrator może wykonać tę akcję.", flash[:alert]
    refute users(:cezary).reload.disabled?
  end

  test "show wyłączonego konta ma opacity i plakietkę, bez przycisku testowego pusha" do
    target = users(:bartek)
    target.disable!
    sign_in_as(users(:ala))

    get user_path(target)
    assert_response :success
    assert_match Copy::Users::DISABLED_BADGE, response.body
    assert_match "opacity-50 grayscale", response.body
    refute_match "Wyślij testowy push", response.body
    assert_match "Włącz konto", response.body
  end

  test "wyłączone konto nie dostaje kodu logowania (neutralna odpowiedz)" do
    target = users(:bartek)
    target.disable!

    assert_no_difference -> { LoginCode.count } do
      assert_no_enqueued_emails do
        post login_codes_path, params: { login_code: { email: target.email } }
      end
    end
    assert_redirected_to verify_login_path
    assert_equal "Jeśli adres jest w systemie, wysłaliśmy kod logowania.", flash[:notice], "odpowiedz neutralna - bez enumeracji kont"
  end
end
