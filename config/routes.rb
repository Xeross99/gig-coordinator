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
    resource :participation, only: %i[create destroy], path: "uczestnictwo"
  end
  resources :hosts,              only: :index,             path: "organizatorzy"
  resources :users,              only: :index,             path: "pracownicy"
  resource  :profile,            only: %i[edit update],    path: "profil"
  resources :push_subscriptions, only: %i[create destroy], path: "subskrypcje-push"

  # PWA manifest + service worker are served from /public as static files.
end
