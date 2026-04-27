Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth (5-digit code) — paths PL, helpers stay English for view/test compatibility.
  get    "logowanie",             to: "sessions#new",        as: :login
  post   "kody-logowania",        to: "login_codes#create",  as: :login_codes
  get    "logowanie/weryfikacja", to: "login_codes#new",     as: :verify_login
  post   "logowanie/weryfikacja", to: "login_codes#verify"
  delete "sesja",                 to: "sessions#destroy",    as: :session

  # Host panel (URL /panel/..., controllers HostAdmin::*)
  namespace :host, path: "panel", module: "host_admin" do
    root "events#index"
    resources :events,  path: "eventy"
    resource  :profile, only: %i[edit update], path: "profil"
  end

  # Worker app (root = events feed)
  root "events#index"
  resources :events, only: %i[index show new create edit update destroy], path: "eventy", path_names: { new: "nowy", edit: "edytuj" } do
    member { get :history, path: "historia" }
    resource :participation, only: %i[create destroy], path: "uczestnictwo" do
      post :accept
      post :decline
    end
    resource :chat, only: :show, path: "czat" do
      resources :messages, only: :create, path: "wiadomosci"
    end
    resource :carpool_offer, only: %i[create destroy], path: "podwozka"
    resources :carpool_requests, only: %i[create destroy], path: "podwozki-zapytania" do
      member do
        post :accept
        post :decline
      end
    end
  end
  resources :hosts, except: :destroy, path: "organizatorzy", path_names: { new: "nowy", edit: "edytuj" }
  resources :users, path: "pracownicy", path_names: { new: "nowy", edit: "edytuj" } do
    collection do
      get :prompt, path: "prompt" # endpoint dla Lexxy @mentions w czacie
    end
  end
  resource  :profile, only: %i[edit update], path: "profil"
  resources :push_subscriptions, only: %i[create destroy], path: "subskrypcje-push"
  get "informacje", to: "info#show",    as: :info
  get "poradnik",   to: "info#install", as: :install_guide

  # Render dynamic PWA files from app/views/pwa/*. `Rails::PwaController` inherits from
  # `ActionController::Base` (not our `ApplicationController`), so it bypasses
  # `allow_browser :modern` — push services/crawlers without a User-Agent still get the
  # real manifest/service-worker instead of a "please upgrade" HTML page.
  get "manifest"       => "rails/pwa#manifest",       as: :pwa_manifest,       defaults: { format: :json }
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }
end
