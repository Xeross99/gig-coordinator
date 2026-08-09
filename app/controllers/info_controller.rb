class InfoController < ApplicationController
  before_action :require_user!, only: %i[show support]

  layout -> { Current.session.present? ? "application" : "auth" }, only: :install

  def show; end

  def install; end

  def support; end
end
