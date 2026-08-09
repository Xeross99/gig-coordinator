Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth (5-digit code) — paths PL, helpers stay English for view/test compatibility.
  get    "logowanie",             to: "sessions#new",        as: :login
  post   "kody-logowania",        to: "login_codes#create",  as: :login_codes
  get    "logowanie/weryfikacja", to: "login_codes#new",     as: :verify_login
  post   "logowanie/weryfikacja", to: "login_codes#verify"
  delete "sesja",                 to: "sessions#destroy",    as: :session
  delete "sesje/:id",             to: "sessions#destroy_remote", as: :remote_session

  # Host panel (URL /panel/..., controllers HostAdmin::*)
  namespace :host, path: "panel", module: "host_admin" do
    root "events#index"
    resources :events,           path: "eventy"
    resources :event_campaigns,  path: "kampanie", path_names: { new: "nowa", edit: "edytuj" }
    resource  :profile,          only: %i[edit update], path: "profil"
  end

  # Worker app (root = events feed)
  root "events#index"
  resources :events, path: "eventy", path_names: { new: "nowy", edit: "edytuj" } do
    member do
      get :history,  path: "historia"
      get :calendar, path: "kalendarz"
    end
    resource :participation, only: %i[create destroy], path: "uczestnictwo" do
      post :accept
      post :decline
    end
    resources :swap_proposals, only: [ :create ], path: "propozycje-wymiany" do
      member do
        post :accept
        post :decline
      end
    end
    resource :carpool_offer, only: %i[create destroy], path: "podwozka"
    resource :carpool_trip, only: [], path: "podwozka/trasa" do
      post :depart   # Wyjeżdżam
      post :pickup   # Jestem u: X (param: user_id)
      post :cancel   # Anuluj wyjazd
    end
    resources :carpool_requests, only: %i[create destroy], path: "podwozki-zapytania" do
      member do
        post :accept
        post :decline
      end
    end
  end
  resources :event_campaigns,
            only: %i[show new create edit update destroy],
            path: "kampanie",
            path_names: { new: "nowa", edit: "edytuj" } do
    member { get :history, path: "historia" }
    resource :campaign_participation, only: %i[create destroy], path: "uczestnictwo" do
      post :accept
      post :decline
    end
  end
  resources :hosts, except: :destroy, path: "gospodarze", path_names: { new: "nowy", edit: "edytuj" }
  resources :users, path: "kurolapacze", path_names: { new: "nowy", edit: "edytuj" } do
    member do
      post :test_push, path: "testowy-push"
      post :toggle_disabled, path: "przelacz-konto"
    end
  end
  resource :profile, only: %i[edit update], path: "profil" do
    post :regenerate_calendar_token, path: "kalendarz/regeneruj"
  end

  # Subskrypcja kalendarza (.ics feed) — token-based auth, bo Apple Calendar /
  # Google Calendar nie wysyłają cookies przy pollingu. Token w URL = wystarczy
  # do autoryzacji, regenerate unieważnia stary URL.
  get "kalendarz/:token.ics", to: "calendar_feeds#show",
                              as: :calendar_feed,
                              defaults: { format: :ics },
                              constraints: { token: /[a-f0-9]{40}/ }
  resources :push_subscriptions, only: %i[create destroy], path: "subskrypcje-push" do
    collection { post :test, path: "test" }
  end
  get "prywatnosc", to: "pages#privacy", as: :privacy
  get "informacje", to: "info#show",    as: :info
  get "poradnik",   to: "info#install", as: :install_guide
  get "wesprzyj",   to: "info#support", as: :support
  get "statystyki", to: "stats#index",  as: :stats

  # Render dynamic PWA files from app/views/pwa/*. `Rails::PwaController` inherits from
  # `ActionController::Base` (not our `ApplicationController`), so it bypasses
  # `allow_browser :modern` — push services/crawlers without a User-Agent still get the
  # real manifest/service-worker instead of a "please upgrade" HTML page.
  get "manifest"       => "rails/pwa#manifest",       as: :pwa_manifest,       defaults: { format: :json }
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }
end
