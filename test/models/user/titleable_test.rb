require "test_helper"

# Teksty rangi (etykieta, ikona, kolor plakietki, opisy) są kluczowane wartością
# enuma `title` i leżą jako hashe w User::Titleable. Wcześniej mieszkały w
# pl.yml — brakujący wpis renderował się wtedy jako „Translation missing"
# zamiast wybuchnąć, więc dorzucenie szóstej rangi do enuma mogło po cichu
# zostawić dziury na /informacje i w mailu awansowym. Ten test pilnuje kompletu.
class User::TitleableTest < ActiveSupport::TestCase
  test "każda ranga ma etykietę, ikonę, kolor plakietki i opis w 3 os." do
    User.titles.keys.each do |title|
      assert User::TITLE_LABELS[title].present?,       "brak etykiety dla rangi #{title}"
      assert User::TITLE_ICONS[title].present?,        "brak ikony dla rangi #{title}"
      assert User::TITLE_BADGE_COLORS[title].present?, "brak koloru plakietki dla rangi #{title}"
      assert User::TITLE_DESCRIPTIONS[title].present?, "brak opisu (3 os.) dla rangi #{title}"
    end
  end

  # Wariant w 2 os. zasila mail awansowy, który celowo nie wysyła się na rangę
  # startową — komplet liczy się więc dla wszystkich rang POZA zoltodziobem.
  test "każda ranga poza startową ma opis w 2 os., a zoltodziob go nie ma" do
    (User.titles.keys - [ "zoltodziob" ]).each do |title|
      assert User::TITLE_DESCRIPTIONS_PERSONAL[title].present?, "brak opisu osobowego dla rangi #{title}"
    end
    assert_nil User::TITLE_DESCRIPTIONS_PERSONAL["zoltodziob"],
               "zoltodziob nie powinien mieć wariantu osobowego — nigdy nie wysyłamy tego maila"
  end

  test "display_title i title_icon czytają z hashy" do
    user = User.new(title: :mistrz_piora)
    assert_equal "Mistrz Pióra", user.display_title
    assert_equal "👑",           user.title_icon
  end
end
