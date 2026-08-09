require "test_helper"

class InfoControllerTest < ActionDispatch::IntegrationTest
  test "GET /poradnik is public (auth layout) for anonymous visitors" do
    get install_guide_path
    assert_response :success
    # Public path — no navbar dropdown is rendered in the auth layout, which
    # confirms the layout switched on signed_in? = false.
    assert_no_match "app-navbar", response.body
  end

  test "GET /poradnik for signed-in user renders in the application layout" do
    sign_in_as(users(:ala))
    get install_guide_path
    assert_response :success
    # Application layout injects the navbar with the user block.
    assert_match "app-navbar",             response.body
    assert_match users(:ala).display_name, response.body
  end

  test "GET /informacje requires login" do
    get info_path
    assert_redirected_to login_path
  end

  test "GET /informacje documents Kurnikowy Komendant event-creation rules" do
    sign_in_as(users(:ala))
    get info_path
    assert_response :success
    # The doc describes both ranks that can plan events and the disabled-button
    # behavior when a komendant has no managed hosts.
    assert_match User::TITLE_LABELS["mistrz_piora"],        response.body
    assert_match User::TITLE_LABELS["kurnikowy_komendant"], response.body
    assert_match "wyszarzony",                              response.body
  end

  test "GET /informacje renders the (3rd person) rank_descriptions for every rank" do
    sign_in_as(users(:ala))
    get info_path
    assert_response :success
    User.titles.keys.each do |title|
      desc = User::TITLE_DESCRIPTIONS[title]
      assert_match desc, response.body, "opis rangi #{title} musi być na /informacje"
    end
  end

  test "GET /informacje informuje, że żółtodziób nie zapisuje się i nie dostaje pushy" do
    sign_in_as(users(:ala))
    get info_path
    assert_response :success
    # Akapit pod "Planowanie zleceń" + sekcja Powiadomienia.
    assert_match "w ogóle się nie zapisuje", response.body
    assert_match "nie dostaje pusha o nowym zleceniu wcale", response.body
  end

  test "GET /informacje wspomina o mailach awansu rangi" do
    sign_in_as(users(:ala))
    get info_path
    assert_response :success
    assert_match "każdym awansie rangi", response.body
  end

  test "GET /wesprzyj requires login" do
    get support_path
    assert_redirected_to login_path
  end

  test "GET /wesprzyj pokazuje cennik i zajawkę kart dla konta bez premium" do
    sign_in_as(users(:bartek))
    get support_path
    assert_response :success
    assert_match "Karta kurołapacza", response.body
    assert_match "29,99 zł",          response.body
    # zajawka: karty widoczne, ale bez pickera (wybór tylko w /profil/edit)
    assert_select "img[src*=?]", "player_cards/traktor"
    assert_select "input[type=radio]", count: 0
  end

  test "GET /wesprzyj dla konta premium dziękuje i linkuje do wyboru karty w profilu" do
    users(:bartek).update!(premium: true)
    sign_in_as(users(:bartek))
    get support_path
    assert_response :success
    assert_match "Dzięki za wsparcie!", response.body
    assert_select "a[href=?]", edit_profile_path
  end
end
