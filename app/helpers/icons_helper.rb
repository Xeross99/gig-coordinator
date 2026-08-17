module IconsHelper
  ICONS_DIR = Rails.root.join("app/assets/images/icons")

  # Wkleja ikonę INLINE, zamiast przez `image_tag`. Ikony są malowane z zewnątrz
  # (`fill="currentColor"` + klasa `text-*` na wywołaniu), a treść `<img>` jest
  # osobnym dokumentem, do którego CSS strony nie sięga — przez `image_tag`
  # wyszłyby czarne i w domyślnym rozmiarze.
  #
  # Klasę wstrzykujemy podmianą w znaczniku `<svg`, bo plik jej nie zawiera:
  # ta sama ikona bywa `size-5 text-white` na osi czasu i `size-3` w plakietce.
  def icon(name, class_name: "size-5")
    svg = IconsHelper.read(name)
    return "".html_safe if svg.nil?

    svg.sub("<svg", %(<svg class="#{ERB::Util.html_escape(class_name)}")).html_safe
  end

  # Poza developmentem plik czytamy raz — w devie za każdym razem, żeby podmiana
  # ikony była widoczna bez restartu (Rails nie przeładowuje app/assets).
  def self.read(name)
    return load_file(name) if Rails.env.development?

    @cache ||= {}
    @cache.fetch(name) { @cache[name] = load_file(name) }
  end

  def self.load_file(name)
    file = ICONS_DIR.join("#{name}.svg")
    return file.read if file.exist?

    Rails.logger.warn("[icons] brak pliku #{file}")
    nil
  end
  private_class_method :load_file
end
