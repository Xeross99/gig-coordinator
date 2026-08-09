require "open3"
require "json"

module Maintenance
  class DatabaseBackupJob < ApplicationJob
    queue_as :default

    RETENTION = 30
    DB_PATH = Rails.root.join("storage", "production.sqlite3").freeze

    def perform
      raise "Backup runs in production only" unless Rails.env.production?

      require "google/cloud/storage"

      project_id = Rails.application.credentials.dig(:gcs, :project_id) or raise "Missing credentials.gcs.project_id"
      bucket_name = Rails.application.credentials.dig(:gcs, :bucket) or raise "Missing credentials.gcs.bucket"
      service_account_json = Rails.application.credentials.dig(:gcs, :service_account_json) or raise "Missing credentials.gcs.service_account_json"

      timestamp = Time.now.utc.strftime("%Y-%m-%d_%H-%M-%S")
      file_name = "chicken_production_#{timestamp}.sql.gz"
      local_path = Rails.root.join("tmp", file_name).to_s

      dump_to_gzip(local_path)

      begin
        storage = Google::Cloud::Storage.new(project_id: project_id, credentials: JSON.parse(service_account_json))
        bucket = storage.bucket(bucket_name, skip_lookup: true)
        bucket.create_file(local_path, file_name)
        prune_old_backups(bucket)
      ensure
        File.delete(local_path) if File.exist?(local_path)
      end
    end

    private

    def dump_to_gzip(local_path)
      statuses = Open3.pipeline(
        [ "sqlite3", DB_PATH.to_s, ".dump" ],
        [ "gzip" ],
        out: local_path
      )
      failed = statuses.find { |s| !s.success? }
      raise "Backup pipeline failed (exit #{failed.exitstatus})" if failed
    end

    def prune_old_backups(bucket)
      files = bucket.files.all.to_a
      return if files.size <= RETENTION

      files.sort_by(&:updated_at).first(files.size - RETENTION).each(&:delete)
    end
  end
end
