# Sprząta subskrypcje-zombie: endpointy po reinstalacji PWA / wyczyszczeniu
# przeglądarki, które push service (zwłaszcza Apple) dalej przyjmuje z HTTP 201,
# ale żadne urządzenie ich nie wyświetla. Serwer nie odróżni takiej subskrypcji
# od żywej po samej wysyłce — za to żywe urządzenie odświeża `updated_at`
# heartbeatem przy każdym otwarciu apki (PushSubscriptionsController#create).
#
# Zasada bezpieczeństwa: kasujemy TYLKO gdy user ma świeższą subskrypcję —
# nigdy nie uciszamy kogoś całkowicie. Drugie urządzenie nieotwierane od
# STALE_AFTER (np. zapasowy tablet) też poleci, ale zarejestruje się na nowo
# przy pierwszym otwarciu — akceptowalny koszt.
class PushSubscriptionPruneJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 60.days

  def perform
    cutoff = STALE_AFTER.ago
    pruned = 0

    PushSubscription.where(updated_at: ...cutoff).find_each do |sub|
      next unless PushSubscription.where(user_id: sub.user_id)
                                  .where(updated_at: cutoff..).exists?
      sub.destroy
      pruned += 1
    end

    Rails.logger.info("[Push] prune: removed #{pruned} stale subscription(s)")
  end
end
