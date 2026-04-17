Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth (magic link) — paths PL, helpers stay English for view/test compatibility.
  get    "logowanie",             to: "sessions#new",       as: :login
  post   "linki-logowania",       to: "magic_links#create", as: :magic_links
  get    "logowanie/weryfikacja", to: "magic_links#show",   as: :verify_magic_link
  delete "sesja",                 to: "sessions#destroy",   as: :session

  # Host panel (URL /panel/..., controllers HostAdmin::*)
  namespace :host, path: "panel", module: "host_admin" do
    root "events#index"
    resources :events,  path: "eventy"
    resource  :profile, only: %i[edit update], path: "profil"
  end

  # Worker app (root = events feed)
  root "events#index"
  resources :events, only: %i[index show], path: "eventy" do
    resource :participation, only: %i[create destroy], path: "uczestnictwo" do
      post :accept
      post :decline
    end
  end
  resources :hosts,              only: :index,             path: "organizatorzy"
  resources :users,              only: :index,             path: "pracownicy"
  resource  :profile,            only: %i[edit update],    path: "profil"
  resources :push_subscriptions, only: %i[create destroy], path: "subskrypcje-push"
  get "informacje", to: "info#show", as: :info

  # Render dynamic PWA files from app/views/pwa/*. `Rails::PwaController` inherits from
  # `ActionController::Base` (not our `ApplicationController`), so it bypasses
  # `allow_browser :modern` — push services/crawlers without a User-Agent still get the
  # real manifest/service-worker instead of a "please upgrade" HTML page.
  get "manifest"       => "rails/pwa#manifest",       as: :pwa_manifest,       defaults: { format: :json }
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }
end
