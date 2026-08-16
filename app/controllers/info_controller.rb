class InfoController < ApplicationController
  # /informacje/instalacja jest publiczne — reszta wymaga zalogowania.
  skip_before_action :require_user!, only: :install

  layout -> { Current.session.present? ? "application" : "auth" }, only: :install

  def show; end

  def install; end

  def support; end
end
