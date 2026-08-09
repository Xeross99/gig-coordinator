class StatsController < ApplicationController
  before_action :require_user!

  def index
    @trophies = StatsService.compute
  end
end
