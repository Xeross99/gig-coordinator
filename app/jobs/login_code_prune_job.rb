class LoginCodePruneJob < ApplicationJob
  queue_as :default

  RETENTION = 30.days

  def perform
    pruned = LoginCode.where(created_at: ...RETENTION.ago).delete_all

    Rails.logger.info("[Auth] prune: removed #{pruned} expired login code(s)")
  end
end
