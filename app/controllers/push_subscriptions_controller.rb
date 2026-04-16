class PushSubscriptionsController < ApplicationController
  before_action :require_user_json!
  skip_forgery_protection

  def create
    sub = current_user.push_subscriptions.find_by(endpoint: sub_params[:endpoint])
    status = sub ? :ok : :created
    sub ||= current_user.push_subscriptions.create!(sub_params)
    render json: { id: sub.id }, status: status
  end

  def destroy
    sub = current_user.push_subscriptions.find_by(endpoint: params[:id]) ||
          current_user.push_subscriptions.find_by(id: params[:id])
    sub&.destroy
    head :no_content
  end

  private

  def sub_params
    params.expect(push_subscription: %i[endpoint p256dh_key auth_key])
  end

  def require_user_json!
    return if current_user
    head :unauthorized
  end
end
