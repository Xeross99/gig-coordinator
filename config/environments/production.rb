require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # TLS is terminated by the host's reverse proxy, which forwards plain HTTP to
  # us — trust X-Forwarded-Proto so cookies are flagged Secure and generated
  # URLs use https://. force_ssl stays off so direct HTTP access to the VPS
  # (on its non-standard port) keeps working as a fallback.
  config.assume_ssl = true

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Host + port used by mailer/route URL helpers. Read from env so we can change
  # hosting without a redeploy: PUBLIC_HOST, PUBLIC_PORT, PUBLIC_PROTOCOL come from
  # config/deploy.yml. Defaults are safe fallbacks, not intended to be hit in real use.
  public_host     = ENV.fetch("PUBLIC_HOST", "localhost")
  public_port     = ENV["PUBLIC_PORT"].presence&.to_i
  public_protocol = ENV.fetch("PUBLIC_PROTOCOL", "https")
  url_options     = { host: public_host, protocol: public_protocol }
  url_options[:port] = public_port if public_port
  config.action_mailer.default_url_options      = url_options
  Rails.application.routes.default_url_options  = url_options

  # Gmail SMTP via credentials (google.user_name + google.password = App Password).
  google_creds = Rails.application.credentials.google
  if google_creds&.user_name.present? && google_creds&.password.present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address:              "smtp.gmail.com",
      port:                 587,
      domain:               "gmail.com",
      user_name:            google_creds.user_name,
      password:             google_creds.password,
      authentication:       :plain,
      enable_starttls_auto: true
    }
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Host authorization: the public domain (HTTPS-fronted) plus any extra hosts
  # the deployment answers on — e.g. the raw VPS hostname used as an HTTP
  # fallback. Set via env, not hardcoded, because this repo is public.
  config.hosts << ENV.fetch("PUBLIC_HOST", "localhost")
  ENV.fetch("EXTRA_HOSTS", "").split(",").map(&:strip).reject(&:empty?).each do |extra_host|
    config.hosts << extra_host
  end

  # Health checks come via Kamal Proxy's internal network → exclude.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
