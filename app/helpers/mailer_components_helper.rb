# Komponenty maili transakcyjnych — cienka warstwa nad partialami z
# app/views/mailer_components/. Każdy komponent przyjmuje treść blokiem:
#
#   <%= mail_title "Witaj, #{@user.first_name}!" %>
#
#   <%= mail_paragraph do %>
#     Twoje konto <%= mail_strong "pracownika" %> jest gotowe.
#   <% end %>
#
#   <%= mail_button "Otwórz aplikację", @url %>
#   <%= mail_raw_url @url %>
#
# Blok jest przechwytywany przez `capture`, które zwraca SafeBuffer — dlatego
# tekst z HTML-em składa się tu naturalnie, bez `safe_join` i bez `html_safe`
# na każdym fragmencie. Zmienne wstawiane przez `<%= %>` wewnątrz bloku nadal
# przechodzą przez normalne escapowanie ERB, więc nic nie tracimy na
# bezpieczeństwie — przeciwnie, znika ręczne oznaczanie stringów jako safe.
module MailerComponentsHelper
  # Nagłówek maila (Georgia, wyśrodkowany).
  def mail_title(text = nil, &block)
    render "mailer_components/title", content: mail_content(text, &block)
  end

  # Akapit treści.
  def mail_paragraph(text = nil, &block)
    render "mailer_components/paragraph", content: mail_content(text, &block)
  end

  # Wyróżnienie w akapicie. Klienci pocztowi bywają wybiórczy wobec <style>,
  # więc kolor idzie inline — a że to jedno miejsce, wszystkie maile mają
  # wyróżnienia w tym samym odcieniu. `style:` dokłada reguły dla przypadków
  # jednorazowych (np. white-space:nowrap), nie nadpisując koloru.
  def mail_strong(text = nil, style: nil, &block)
    tag.strong(mail_content(text, &block), style: [ "color:#0c0a09", style ].compact.join(";"))
  end

  # Kod logowania — duży monospace na jasnym kaflu. Nie jest akapitem: ma być
  # łatwy do przepisania z ekranu telefonu i do zaznaczenia jednym tapnięciem.
  def mail_code(code)
    render "mailer_components/code", code: code
  end

  # Okrągła plakietka z emoji nad tytułem (mail awansowy: ikona rangi).
  def mail_icon_badge(icon)
    render "mailer_components/icon_badge", icon: icon
  end

  def mail_button(label, url)
    render "mailer_components/button", label: label, url: url
  end

  def mail_raw_url(url)
    render "mailer_components/raw_url", url: url
  end

  private

  # Blok wygrywa z argumentem — pozwala mieszać oba style w jednym mailu
  # (krótkie teksty argumentem, składane blokiem).
  def mail_content(text = nil, &block)
    block ? capture(&block) : text
  end
end
