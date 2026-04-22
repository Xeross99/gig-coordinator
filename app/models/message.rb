class Message < ApplicationRecord
  belongs_to :event
  belongs_to :user

  validates :body, presence: true, length: { maximum: 2_000 }
  validate :body_has_content

  # Broadcast appenda do czatu eventu. Strumień `[event, :chat]` subskrybuje
  # ChatsController#show — użytkownicy nie otwarci na czacie nie odbierają
  # niczego (ramka turbo nie subskrybuje kanału aż zostanie fetchnięta).
  MENTION_HREF = %r{\A/pracownicy/(\d+)\z}.freeze

  after_create_commit :broadcast_append_to_chat
  after_create_commit :notify_mentioned_users

  # Parsuje HTML body, wyciąga user_id ze wszystkich `<a href="/pracownicy/:id">`
  # (te linki produkuje Lexxy z `<lexxy-prompt>` — mentions). Wysyła push do
  # każdego wspomnianego usera, pomijając autora wiadomości (bez sensu pingować
  # siebie samego).
  def mentioned_user_ids
    ids = Nokogiri::HTML5.fragment(body.to_s)
      .css("a[href]")
      .map { |n| n["href"][MENTION_HREF, 1] }
      .compact.map(&:to_i).uniq
    ids - [ user_id ]
  end

  private

  # Lexxy serializuje puste pole jako `<p><br></p>` lub `<p></p>` — dla Railsów
  # `body.blank?` zwraca false, bo to niepusty string. Trzeba sparsować HTML
  # i sprawdzić faktyczny text content (plus fakt, że nie ma żadnych interaktywnych
  # elementów jak osadzony mention).
  def body_has_content
    if body.blank?
      errors.add(:body, :blank)
      return
    end

    fragment = Nokogiri::HTML5.fragment(body)
    text_blank      = fragment.text.strip.empty?
    has_interactive = fragment.css("a, img").any?
    errors.add(:body, :blank) if text_blank && !has_interactive
  end

  def broadcast_append_to_chat
    broadcast_append_to [ event, :chat ],
                        target:  ActionView::RecordIdentifier.dom_id(event, :chat_messages),
                        partial: "messages/message",
                        locals:  { message: self }
  end

  def notify_mentioned_users
    mentioned_user_ids.each do |uid|
      WebPushNotifier.perform_later(:mention, message_id: id, user_id: uid)
    end
  end
end
