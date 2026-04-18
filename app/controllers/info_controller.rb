class InfoController < ApplicationController
  before_action :require_user!, only: :show
  # Anonymous visitors (linked from /logowanie) get the minimal auth layout.
  # Signed-in users reach this via the dropdown menu and keep the normal
  # application chrome (navbar + breadcrumb).
  layout -> { signed_in? ? "application" : "auth" }, only: :install

  def show
  end

  def install
  end
end
