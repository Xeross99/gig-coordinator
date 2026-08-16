class StatsController < ApplicationController
  def index
    @trophies = StatsService.compute
  end
end
