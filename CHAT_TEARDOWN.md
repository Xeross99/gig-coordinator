# Czat eventu — teardown guide

Pełna lista wszystkiego, co dodano/zmieniono w projekcie dla funkcji czatu
(per-event messaging z Lexxy + @mentions + push + rate-limit + lazy scroll).
Jeśli czat trzeba wyrzucić, zrób wszystko z tej listy — kolejność po
sekcjach nie ma znaczenia, byle rezultat końcowy.

## 1. Rollback migracji

```bash
bin/rails db:rollback STEP=1   # usuwa tabelę `messages`
rm db/migrate/20260421115112_create_messages.rb
```

`db/schema.rb` zregeneruje się automatycznie po kolejnym `db:migrate` (albo
ręcznie przez `bin/rails db:schema:dump`). Zweryfikuj, że zniknął:

```ruby
create_table "messages", force: :cascade do |t|
  t.integer "event_id", null: false
  t.integer "user_id", null: false
  t.text "body", null: false
  ...
end
add_foreign_key "messages", "events"
add_foreign_key "messages", "users"
```

## 2. Plik do skasowania (całkowicie)

Modele i controllery:
- `app/models/message.rb`
- `app/controllers/chats_controller.rb`
- `app/controllers/messages_controller.rb`
- `app/helpers/messages_helper.rb`

Widoki:
- `app/views/chats/show.html.erb`
- `app/views/chats/_form.html.erb`
- `app/views/chats/_sentinel.html.erb`
- `app/views/chats/more.turbo_stream.erb`
- `app/views/messages/_message.html.erb`
- `app/views/users/_mention_card.html.erb`
- `app/views/users/prompt.html.erb`

Stimulus controllery (JS):
- `app/javascript/controllers/chat_form_controller.js`
- `app/javascript/controllers/chat_scroller_controller.js`
- `app/javascript/controllers/chat_load_more_controller.js`

Testy:
- `test/models/message_test.rb`
- `test/controllers/chats_controller_test.rb`
- `test/controllers/messages_controller_test.rb`

Puste katalogi do usunięcia po wyżej:
- `app/views/chats/`
- `app/views/messages/`

## 3. Pliki do edycji (revert konkretnych fragmentów)

### `Gemfile`

Usuń:
```ruby
# Lexxy — rich-text editor (Basecamp) używany w czacie eventów do @mentions.
gem "lexxy", "~> 0.9.9.beta"
```

Potem `bundle install` żeby odświeżyć `Gemfile.lock`.

### `config/importmap.rb`

Usuń:
```ruby
pin "lexxy",  to: "lexxy.js"
```

### `app/javascript/application.js`

Usuń:
```js
import * as Lexxy from "lexxy"

Lexxy.configure({
  default: {
    toolbar:     false,
    attachments: false,
  },
})
```

### `app/views/layouts/application.html.erb`

Usuń:
```erb
<%= stylesheet_link_tag "lexxy", "data-turbo-track": "reload" %>
```

### `config/routes.rb`

Wewnątrz `resources :events, ...` bloku usuń:
```ruby
resource :chat, only: :show, path: "czat" do
  resources :messages, only: :create, path: "wiadomosci"
end
```

Wewnątrz `resources :users, ...` bloku usuń:
```ruby
collection do
  get :prompt, path: "prompt" # endpoint dla Lexxy @mentions w czacie
end
```

Jeśli po usunięciu w `resources :users` zostaje pusty blok `do ... end`,
spłaszcz do jednego wiersza bez bloku.

### `app/controllers/users_controller.rb`

Usuń akcję `prompt`:
```ruby
# GET /pracownicy/prompt
def prompt
  @users = User.order(:first_name, :last_name)
  render layout: false
end
```

### `app/models/event.rb`

Usuń:
```ruby
has_many :messages, -> { order(:created_at) }, dependent: :destroy
```

### `app/models/user.rb`

Usuń:
```ruby
has_many :messages, dependent: :destroy
```

### `app/jobs/web_push_notifier.rb`

W `case kind.to_sym` usuń gałąź:
```ruby
when :mention
  message = Message.find(args.fetch(:message_id))
  user    = User.find(args.fetch(:user_id))
  payload = build_payload(:mention, message: message)
  user.push_subscriptions.find_each { |s| send_web_push(s, payload) }
```

W `def build_payload` usuń parametr `message: nil` oraz gałąź:
```ruby
when :mention
  snippet = Nokogiri::HTML5.fragment(message.body).text.strip.truncate(120)
  {
    title: "#{message.user.display_name} wywołał Cię w czacie",
    body:  "#{message.event.name} · #{snippet}",
    url:   url_for.call(message.event)
  }
```

Komentarz nad `def perform` — usuń linijkę `#   perform(:mention, ...)`.

### `app/views/events/show.html.erb`

Na samym dole, POZA `</div>` głównego kontenera, usuń:
```erb
<%# Czat dojeżdża lazy w osobnej ramce — pierwsze malowanie strony (roster +
    przycisk zapisu) nie czeka na żadne zapytanie związane z wiadomościami. %>
<div class="mt-4">
  <%= turbo_frame_tag "event_chat", src: event_chat_path(@event), loading: "lazy" do %>
    <div class="bg-white rounded-xl shadow-sm p-4 text-stone-400 text-sm text-center">
      Wczytuję czat…
    </div>
  <% end %>
</div>
```

### `config/locales/pl.yml`

Usuń:
```yaml
activerecord:
  attributes:
    message:
      body: "Wiadomość"
  errors:
    models:
      message:
        attributes:
          body:
            blank: "nie może być pusta"
```

Pod `participations:` usuń:
```yaml
rate_limited: "Za dużo wiadomości - zwolnij i spróbuj za chwilę."
```

### `config/environments/test.rb`

Przywróć:
```ruby
config.cache_store = :null_store
```

(Oryginał — z `:memory_store` wróciliśmy bo `rate_limit` potrzebował działającego
cache. Po usunięciu rate_limit z czatu `:null_store` jest OK.)

### `app/assets/tailwind/application.css`

Usuń w całości następujące reguły (każda z nich jest wstawiona w jednym bloku,
nie zagnieżdżona — znajdź komentarze i kasuj od komentarza do końca reguły):

- `.mention, a.mention { ... }` + `a.mention` (chip edytora)
- `.mention-card { ... }` + `.mention-card__avatar`, `.mention-card__avatar--initials`, `.mention-card__name`, `.mention-card .inline-flex`
- `.lexxy-prompt-menu-item { ... }`, `.lexxy-prompt-menu-item__avatar`, `.lexxy-prompt-menu-item__avatar--initials`, `.lexxy-prompt-menu-item__text` + `strong`/`.inline-flex` potomne
- `lexxy-editor { max-width: 100%; width: 100%; }`
- `lexxy-editor[toolbar="false"] lexxy-toolbar, .chat-form lexxy-toolbar { display: none !important; }`
- `.lexxy-prompt-menu { max-inline-size: ...; min-inline-size: ...; }`
- `.chat-viewport { mask-image: ...; -webkit-mask-image: ...; }`
- `.chat-editor .lexxy-editor__content { block-size: 3rem ...; max-block-size: 3rem ...; overflow-y: auto; }`

Wszystkie są dopisane poniżej bazowej reguły `.form-select`. Komentarze ERB
zaczynają się od „/\* Lexxy …", „/\* @mention …", „/\* Chat editor …" — łatwo
znaleźć przez Cmd+F.

## 4. Seedy

`db/seeds.rb` nie tworzy żadnych wiadomości, więc nie trzeba nic usuwać.

## 5. Credentials / ENV

Nic. Czat nie wprowadził żadnych nowych sekretów. VAPID pozostaje (używany
przez istniejące kinds pushy: new_event, invitation, promotion, completion).

## 6. Web push

Jeśli chcesz, żeby już wysłane pushe typu `:mention` przestały się ponawiać,
upewnij się że job queue nie ma zaległych job-ów:

```bash
bin/rails runner 'SolidQueue::Job.where("arguments LIKE ?", "%mention%").destroy_all'
```

Normalnie Solid Queue usunie je z handled failures po TTL, ale lepiej wyczyścić
od razu żeby po deploy-u bez kodu obsługującego `:mention` nie leciały wyjątki
„unknown kind: mention" z `WebPushNotifier`.

## 7. Weryfikacja

Po wszystkim odpal:
```bash
bin/rails test        # nie powinno być testów związanych z czatem
bin/rubocop           # lint
bin/brakeman          # audyt — żeby nic się nie zepsuło
```

I w przeglądarce:
- `/eventy/:id` — brak sekcji czatu na dole.
- `/eventy/:id/czat` — 404.
- `/pracownicy/prompt` — 404.
- Strona eventu ładuje się szybciej (mniej about:lazy frame'ów).

## 8. Co zostaje (celowo, bo nie należy do czatu)

Te rzeczy dodałem PRZED czatem i zostają w kodzie niezależnie:
- `HostBlock` model + migracja + UI (blokady organizator ↔ user).
- `app/javascript/lib/haptic.js` + import w `application.js` (haptics na przyciskach zapisu).
- `app/javascript/controllers/turbo_confirm_controller.js`, `pull_to_refresh_controller.js`, itd. — istniały wcześniej.
- Pin `@rails/activestorage` w importmap — używany przez istniejące photo uploads, nie czat.

Nic z powyższego nie trzeba ruszać.
