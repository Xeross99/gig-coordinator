class PushSubscriptionsController < ApplicationController
  before_action :require_user_json!, only: %i[create destroy]
  before_action :require_user!,      only: :test
  skip_forgery_protection            only: %i[create destroy]

  # Klient POST-uje aktualną subskrypcję przy KAŻDYM otwarciu PWA (connect()
  # w push_subscription_controller.js), więc create działa jak heartbeat:
  # `updated_at` = ostatni moment, w którym urządzenie potwierdziło, że ta
  # subskrypcja u niego żyje. Na tym opiera się PushSubscriptionPruneJob
  # (sprzątanie zombie — endpointów po reinstalacji PWA, które push service
  # dalej przyjmuje, ale żaden telefon ich nie wyświetla).
  # Lookup po endpoincie globalnie (nie per user): endpoint identyfikuje
  # urządzenie — gdy na tym samym telefonie zaloguje się ktoś inny,
  # przepinamy subskrypcję na niego zamiast wykrzaczyć się na unique index.
  def create
    sub = PushSubscription.find_or_initialize_by(endpoint: sub_params[:endpoint])
    status = sub.new_record? ? :created : :ok
    sub.assign_attributes(sub_params.merge(user: Current.user))
    sub.changed? ? sub.save! : sub.touch
    render json: { id: sub.id }, status: status
  end

  def destroy
    endpoint = params.dig(:push_subscription, :endpoint) || params[:id]
    sub = Current.user.push_subscriptions.find_by(endpoint: endpoint) ||
          Current.user.push_subscriptions.find_by(id: params[:id])
    sub&.destroy
    head :no_content
  end

  def test
    if Current.user.push_subscriptions.exists?
      WebPushNotifier.perform_later(:test, user_id: Current.user.id)
      redirect_to edit_profile_path, notice: "Wysłano testowe powiadomienie. Powinno przyjść za chwilę."
    else
      redirect_to edit_profile_path, alert: "Brak aktywnej subskrypcji push — najpierw włącz powiadomienia."
    end
  end

  private

  def sub_params
    params.expect(push_subscription: %i[endpoint p256dh_key auth_key])
  end

  def require_user_json!
    return if Current.user
    head :unauthorized
  end
end
