class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  include Trackable, Authenticatable
end
