require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:ala)) }

  test "GET edit wires the photo-upload Stimulus controller to the direct uploads endpoint" do
    get edit_profile_path
    assert_response :success
    assert_select "form[data-controller~=?][data-photo-upload-url-value=?]", "photo-upload", rails_direct_uploads_path
    assert_select "form[data-turbo=?]", "false"
    assert_select "input[type=file][data-photo-upload-target=input][accept=?]", "image/*"
    assert_select "input[type=hidden][name=?][disabled]", "user[photo]"
    assert_select "button[type=button][data-action=?]", "click->photo-upload#selectFile", text: /Wybierz zdjęcie/
  end

  test "PATCH update attaches a photo from a direct-upload signed_id" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-png"),
      filename: "me.png",
      content_type: "image/png"
    )

    patch profile_path, params: { user: { photo: blob.signed_id } }

    assert_redirected_to edit_profile_path
    assert_equal "Zapisano", flash[:notice]
    assert users(:ala).reload.photo.attached?
    assert_equal blob.id, users(:ala).reload.photo.blob.id
  end

  test "PATCH update still accepts a multipart photo upload" do
    file = Rack::Test::UploadedFile.new(StringIO.new("fake-png"), "image/png", original_filename: "me.png")

    patch profile_path, params: { user: { photo: file } }

    assert_redirected_to edit_profile_path
    assert users(:ala).reload.photo.attached?
  end

  test "PATCH update without a photo param leaves the existing attachment intact" do
    users(:ala).photo.attach(
      io: StringIO.new("original"),
      filename: "original.png",
      content_type: "image/png"
    )
    original_blob_id = users(:ala).photo.blob.id

    # The hidden user[photo] input is rendered `disabled` until DirectUpload
    # fills it, so a bare submit sends no `user` param at all. That's a user
    # clicking „Zapisz zdjęcie" without picking a file — redirect with an alert
    # instead of a 400, and never wipe the existing attachment.
    patch profile_path, params: { user: {} }

    assert_redirected_to edit_profile_path
    assert_equal "Najpierw wybierz zdjęcie.", flash[:alert]
    assert users(:ala).reload.photo.attached?
    assert_equal original_blob_id, users(:ala).reload.photo.blob.id
  end

  test "PATCH update bez żadnego parametru user przekierowuje z alertem" do
    patch profile_path

    assert_redirected_to edit_profile_path
    assert_equal "Najpierw wybierz zdjęcie.", flash[:alert]
  end

  test "hosts cannot reach the worker profile edit" do
    sign_in_as(hosts(:jan))
    get edit_profile_path
    assert_redirected_to login_path
  end

  test "GET edit wyświetla URL kalendarza z aktualnym tokenem" do
    users(:ala).update_column(:calendar_token, "a" * 40)
    get edit_profile_path
    assert_select "input[value*=?]", "/kalendarz/#{'a' * 40}.ics"
  end

  test "POST regenerate_calendar_token rotuje token i odświeża URL" do
    old_token = users(:ala).calendar_token
    post regenerate_calendar_token_profile_path
    assert_redirected_to edit_profile_path
    new_token = users(:ala).reload.calendar_token
    refute_equal old_token, new_token
    assert_match(/\A[a-f0-9]{40}\z/, new_token)
  end

  # --- karty gracza (premium) --------------------------------------------------

  test "GET edit pokazuje picker kart gracza dla konta premium" do
    users(:bartek).update!(premium: true)
    sign_in_as(users(:bartek))
    get edit_profile_path
    assert_select "input[type=radio][name=?]", "user[player_card]"
    assert_select "img[src*=?]", "player_cards/traktor"
  end

  test "GET edit nie pokazuje sekcji kart dla konta bez premium" do
    sign_in_as(users(:bartek))
    get edit_profile_path
    assert_select "input[type=radio][name=?]", "user[player_card]", count: 0
    # cennik i zajawka kart żyją na /wesprzyj, nie w profilu
    refute_match "Karta pracownika", response.body
    assert_select "img[src*=?]", "player_cards/traktor", count: 0
  end

  test "PATCH update zapisuje kartę gracza dla konta premium" do
    users(:bartek).update!(premium: true)
    sign_in_as(users(:bartek))

    patch profile_path, params: { user: { player_card: "kontener" } }

    assert_redirected_to edit_profile_path
    assert_equal "kontener", users(:bartek).reload.player_card
  end

  test "PATCH update z pustą kartą czyści wybór (opcja Brak tła)" do
    users(:bartek).update!(premium: true, player_card: "traktor")
    sign_in_as(users(:bartek))

    patch profile_path, params: { user: { player_card: "" } }

    assert_nil users(:bartek).reload.player_card
  end

  test "PATCH update ucina player_card dla konta bez premium" do
    sign_in_as(users(:bartek))
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-png"), filename: "me.png", content_type: "image/png"
    )

    patch profile_path, params: { user: { photo: blob.signed_id, player_card: "kontener" } }

    assert_nil users(:bartek).reload.player_card
  end

  test "admin ma karty gracza bez własnego premium" do
    assert_nil users(:ala).premium_until, "fixture nie powinna mieć premium_until"

    patch profile_path, params: { user: { player_card: "ladowarka" } }

    assert_equal "ladowarka", users(:ala).reload.player_card
  end

  # Fragment listy urządzeń (bez akapitu wstępnego, który też zawiera frazę
  # „to urządzenie"), żeby asercje kolejności mierzyły realną pozycję wierszy.
  def sessions_list_html
    body = response.body
    from = body.index('<ul class="divide-y divide-stone-100">')
    refute_nil from, "nie znaleziono listy urządzeń w wyrenderowanej stronie"
    body[from, body.index("</ul>", from) - from]
  end

  # Regresja: `@sessions` ładowała tylko akcja `edit`, a `update` renderuje ten
  # sam widok przy nieudanej walidacji — render trafiał wtedy na nil i wywalał
  # się na `.each` zamiast pokazać błąd. Teraz sesje ładuje before_action.
  #
  # Test sprawdza nie tylko „nie wybucha", ale że render jest UŻYTECZNY:
  # jest komunikat walidacji i pełna, poprawnie posortowana lista urządzeń.
  test "PATCH update z nieprawidłową kartą pokazuje błąd i pełną listę urządzeń" do
    user = users(:bartek)
    user.update!(premium: true, player_card: "traktor")
    sign_in_as(user)
    # Świeższa niż bieżąca — samo sortowanie postawiłoby ją pierwszą, więc
    # test faktycznie sprawdza wynoszenie bieżącej sesji na górę.
    other = user.sessions.create!(user_agent: "Mozilla/5.0 (iPhone)", ip_address: "10.0.0.9",
                                  last_seen_at: 1.hour.from_now)

    patch profile_path, params: { user: { player_card: "nieistniejaca-karta" } }

    assert_response :unprocessable_content
    # 1. Komunikat walidacji dotarł do użytkownika.
    assert_select "li", text: /Player card/
    # 2. Sekcja urządzeń wyrenderowała się w komplecie — to ona wcześniej padała.
    list = sessions_list_html
    assert_equal user.sessions.count, list.scan("<li").size
    # 3. Bieżąca sesja nadal pierwsza (kolejność z load_sessions zachowana).
    assert_operator list.index("to urządzenie"), :<, list.index("/sesje/#{other.id}"),
                    "bieżąca sesja powinna być na górze listy"
    # 4. Odrzucona wartość nie została zapisana, poprzednia karta nietknięta.
    assert_equal "traktor", user.reload.player_card
  end

  # Kontrola pozytywna: po wyniesieniu logiki do before_action `edit` działa
  # tak samo jak wcześniej.
  test "GET edit wypisuje wszystkie sesje z bieżącą na pierwszym miejscu" do
    user = users(:bartek)
    sign_in_as(user)
    other = user.sessions.create!(user_agent: "Mozilla/5.0 (iPhone)", ip_address: "10.0.0.9",
                                  last_seen_at: 1.hour.from_now)

    get edit_profile_path

    assert_response :success
    list = sessions_list_html
    assert_equal user.sessions.count, list.scan("<li").size
    assert_operator list.index("to urządzenie"), :<, list.index("/sesje/#{other.id}"),
                    "bieżąca sesja powinna być na górze listy"
  end

  test "PATCH update ignores phone param (admin-managed field)" do
    users(:ala).update!(phone: "111 222 333")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-png"), filename: "me.png", content_type: "image/png"
    )

    patch profile_path, params: { user: { photo: blob.signed_id, phone: "999 999 999" } }

    assert_equal "111 222 333", users(:ala).reload.phone
  end
end
