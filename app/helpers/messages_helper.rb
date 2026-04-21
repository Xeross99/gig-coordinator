module MessagesHelper
  MENTION_TAGS  = %w[p br strong em code pre ul ol li a span blockquote h1 h2 h3].freeze
  MENTION_ATTRS = %w[class href data-user-id data-user-display-name].freeze
  MENTION_HREF  = %r{\A/pracownicy/(\d+)\z}.freeze

  # Renderuje treść wiadomości czatu:
  # 1. Sanitize z whitelistą tagów/atrybutów (obrona przed dowolnym HTML z Lexxy).
  # 2. Wymienia każdy `<a href="/pracownicy/:id">` na bogaty kafelek usera
  #    (awatar + imię + rank badge). Lexxy free-html strips class/data-*
  #    attributes at serialization — ale href linków (LinkNode) przeżywa,
  #    więc rozpoznajemy mentions po URL-u profilu, nie po klasie CSS.
  def render_message_body(message)
    safe_html = sanitize(message.body, tags: MENTION_TAGS, attributes: MENTION_ATTRS)
    doc       = Nokogiri::HTML5.fragment(safe_html)

    mention_links = doc.css("a[href]").select { |n| n["href"] =~ MENTION_HREF }
    return safe_html.html_safe if mention_links.empty?

    ids = mention_links.map { |n| n["href"][MENTION_HREF, 1].to_i }.uniq
    users_by_id = User.where(id: ids).with_attached_photo.index_by(&:id)

    mention_links.each do |node|
      user = users_by_id[node["href"][MENTION_HREF, 1].to_i]
      next unless user

      rendered = render(partial: "users/mention_card", locals: { user: user })
      node.replace(Nokogiri::HTML5.fragment(rendered))
    end

    doc.to_html.html_safe
  end
end
