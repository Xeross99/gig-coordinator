module User::Titleable
  extend ActiveSupport::Concern

  # Wszystko, co opisuje rangę, jest kluczowane wartością enuma `title` i leży
  # obok niego. Wcześniej etykiety, ikony i opisy siedziały w pl.yml pod
  # `user.*` — brakujący klucz renderował się tam jako „Translation missing"
  # zamiast wybuchnąć, a dopisanie rangi do enuma nie wymuszało uzupełnienia
  # tekstów. Teraz komplet pilnuje test (`titleable_test.rb`).

  TITLE_LABELS = {
    "zoltodziob"          => "Żółtodziób",
    "kurzy_pacholek"      => "Kurzy Pachołek",
    "kurnikowy_gangster"  => "Kurnikowy Gangster",
    "kurnikowy_komendant" => "Kurnikowy Komendant",
    "mistrz_piora"        => "Mistrz Pióra"
  }.freeze

  TITLE_ICONS = {
    "zoltodziob"          => "🐣",
    "kurzy_pacholek"      => "🐤",
    "kurnikowy_gangster"  => "🐓",
    "kurnikowy_komendant" => "🎖️",
    "mistrz_piora"        => "👑"
  }.freeze

  TITLE_BADGE_COLORS = {
    "zoltodziob"          => "bg-gray-100 text-gray-600",
    "kurzy_pacholek"      => "bg-green-100 text-green-700",
    "kurnikowy_gangster"  => "bg-blue-100 text-blue-700",
    "kurnikowy_komendant" => "bg-purple-100 text-purple-700",
    "mistrz_piora"        => "bg-yellow-100 text-yellow-800"
  }.freeze

  # Opisy rang w 3 os. — strona /informacje, czytelnik ogląda cudzą hierarchię.
  TITLE_DESCRIPTIONS = {
    "zoltodziob"          => "Startowa ranga każdego nowego kurołapacza. Może przeglądać zlecenia, ale nie zapisuje się na nie i nie dostaje powiadomień o nowych zleceniach. Po awansie zyskuje pełne prawa.",
    "kurzy_pacholek"      => "Pełnoprawny kurołapacz, ale powiadomienie o nowym zleceniu dostaje 5 min po wyższych rangach, żeby tamte miały pierwszeństwo zapisu.",
    "kurnikowy_gangster"  => "Zapisuje się na zlecenia bez ograniczeń i dostaje powiadomienie o nowym zleceniu od razu razem z wyższymi rangami.",
    "kurnikowy_komendant" => "Może planować zlecenia, ale tylko u przypisanych mu gospodarzy.",
    "mistrz_piora"        => "Może planować zlecenia u dowolnego gospodarza oraz otrzymuje automatyczne rezerwacje na nowe zlecenia."
  }.freeze

  # Te same opisy w 2 os. — mail awansowy jest skierowany do konkretnej osoby.
  # Brak `zoltodziob` celowo: to ranga startowa, nigdy nie awansuje się NA nią,
  # więc RankPromotionMailer dla niej nie wysyła (guard w mailerze).
  TITLE_DESCRIPTIONS_PERSONAL = {
    "kurzy_pacholek"      => "Możesz teraz zapisywać się na zlecenia. Powiadomienie o nowym zleceniu dostajesz 5 min po wyższych rangach - wyższe mają chwilę fory na zapis.",
    "kurnikowy_gangster"  => "Zapisujesz się na zlecenia bez ograniczeń i powiadomienie o nowym zleceniu dostajesz od razu razem z wyższymi rangami.",
    "kurnikowy_komendant" => "Możesz teraz planować zlecenia, ale tylko u gospodarzy, do których zostałeś przypisany. Jeśli nikt nie jest jeszcze przypisany - poproś admina.",
    "mistrz_piora"        => "Możesz teraz planować zlecenia u dowolnego gospodarza i dostajesz automatyczne rezerwacje na nowe zlecenia."
  }.freeze

  included do
    enum :title, {
      zoltodziob:          0,
      kurzy_pacholek:      1,
      kurnikowy_gangster:  2,
      kurnikowy_komendant: 3,
      mistrz_piora:        4
    }
  end

  def title_badge_classes
    TITLE_BADGE_COLORS.fetch(title, "bg-gray-100 text-gray-600")
  end

  def display_title
    TITLE_LABELS.fetch(title, title.to_s.humanize)
  end

  def title_icon
    TITLE_ICONS[title]
  end
end
