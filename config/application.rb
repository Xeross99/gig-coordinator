require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module GigCoordinator
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Aplikacja jest jednojęzyczna — copy żyje w kodzie (stałe w app/lib/copy.rb
    # i hashe przy enumach), a i18n obsługuje już tylko formaty date/time/number
    # oraz komunikaty walidacji z rails-i18n.
    config.i18n.default_locale = :pl
    config.i18n.available_locales = %i[pl]
    config.time_zone = "Warsaw"

    # Dane administratora na stronie polityki prywatności. Nie są zaszyte w
    # kodzie, bo repozytorium jest publiczne, a to dane osobowe — realne
    # wartości wstrzykuje env produkcyjny (config/deploy.production.yml).
    config.x.admin_name    = ENV.fetch("ADMIN_NAME", "administrator aplikacji")
    config.x.contact_email = ENV.fetch("CONTACT_EMAIL", "kontakt@example.com")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
