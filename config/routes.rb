Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth (magic link)
  get    "login",        to: "sessions#new",         as: :login
  post   "magic_links",  to: "magic_links#create",   as: :magic_links
  get    "login/verify", to: "magic_links#show",     as: :verify_magic_link
  delete "session",      to: "sessions#destroy",     as: :session

  # Host panel (URL /host/..., controllers HostAdmin::*)
  namespace :host, module: "host_admin" do
    root "events#index"
    resources :events
    resource  :profile, only: %i[edit update]
  end

  # Worker app (root = events feed)
  root "events#index"
  resources :events, only: %i[index show] do
    resource :participation, only: %i[create destroy]
  end
  resources :push_subscriptions, only: %i[create destroy]

  # PWA
  get "manifest.webmanifest", to: "pwa#manifest",       as: :pwa_manifest
  get "service-worker.js",    to: "pwa#service_worker", as: :pwa_service_worker
end
