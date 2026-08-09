namespace :maintenance do
  desc "Download latest production DB backup from GCS and replace the local development DB"
  task import_database: :environment do
    raise "Cannot import into '#{Rails.env}' — only development is allowed." unless Rails.env.development?

    require "google/cloud/storage"
    require "json"

    project_id = Rails.application.credentials.dig(:gcs, :project_id) or abort "Missing credentials.gcs.project_id"
    bucket_name = Rails.application.credentials.dig(:gcs, :bucket) or abort "Missing credentials.gcs.bucket"
    sa_json = Rails.application.credentials.dig(:gcs, :service_account_json) or abort "Missing credentials.gcs.service_account_json"

    db_path = Rails.root.join("storage", "development.sqlite3").to_s
    dump_path = Rails.root.join("tmp", "production_import.sql").to_s
    gz_path = "#{dump_path}.gz"

    storage = Google::Cloud::Storage.new(project_id: project_id, credentials: JSON.parse(sa_json))
    bucket = storage.bucket(bucket_name, skip_lookup: true)

    puts "Looking for latest backup in #{bucket_name}..."
    latest = bucket.files.all.max_by(&:updated_at) or abort "No backups found in bucket #{bucket_name}."

    puts "Downloading #{latest.name} (#{latest.size} bytes)..."
    latest.download(gz_path)

    puts "Replacing #{db_path}..."
    ActiveRecord::Base.connection_pool.disconnect!
    [ db_path, "#{db_path}-shm", "#{db_path}-wal" ].each { |p| File.delete(p) if File.exist?(p) }

    system("gunzip -f #{gz_path}", exception: true)
    system("sqlite3 #{db_path} < #{dump_path}", exception: true)
    File.delete(dump_path)

    ActiveRecord::Base.establish_connection
    deleted = PushSubscription.delete_all
    puts "Wyczyszczono #{deleted} subskrypcji push (safety: dev nie wysyła pushów)."

    puts "Done. Run `rake maintenance:import_photos` to pull Active Storage blobs. Restart bin/dev to pick up the new DB."
  end

  desc "Download Active Storage blobs (photos) from production server via Kamal"
  task import_photos: :environment do
    raise "Cannot import into '#{Rails.env}' — only development is allowed." unless Rails.env.development?

    local_storage = Rails.root.join("storage").to_s
    tmp_tar = Rails.root.join("tmp", "prod_storage.tar.gz").to_s

    puts "Downloading Active Storage files from production..."

    # Use kamal to exec a tar inside the container, then pipe it back via SSH
    # The container volume is at /rails/storage — we want everything under the
    # Active Storage blob directories (directories like "ab/cd/<key>").
    # Namiary na serwer nie są w repo (jest publiczne) — bierzemy je z ENV,
    # tych samych wartości używa config/deploy.production.yml.
    ssh_port  = ENV["DEPLOY_SSH_PORT"]
    ssh_hostname = ENV["DEPLOY_SSH_HOST"]
    container = ENV.fetch("DEPLOY_CONTAINER", "gig-coordinator-web")
    if ssh_port.blank? || ssh_hostname.blank?
      abort "Ustaw DEPLOY_SSH_HOST i DEPLOY_SSH_PORT (patrz config/deploy.production.yml)."
    end
    ssh_host = "#{ENV.fetch('DEPLOY_SSH_USER', 'root')}@#{ssh_hostname}"

    # Find the running container name
    container_id = `ssh -p #{ssh_port} #{ssh_host} "docker ps --filter name=#{container} -q" 2>/dev/null`.strip
    if container_id.empty?
      abort "Nie znaleziono działającego kontenera #{container}. Czy aplikacja jest zdeployowana?"
    end

    puts "Found container #{container_id}, creating tarball..."
    system(
      "ssh", "-p", ssh_port.to_s, ssh_host,
      "docker exec #{container_id} tar czf - -C /rails/storage .",
      out: tmp_tar,
      exception: true
    )

    puts "Extracting to #{local_storage}..."
    system("tar", "xzf", tmp_tar, "-C", local_storage, exception: true)
    File.delete(tmp_tar)

    puts "Done. #{Dir.glob("#{local_storage}/**/*").count { |f| File.file?(f) }} files in storage/."
  end

  desc "Import both DB and photos from production"
  task import_all: %i[import_database import_photos]
end
