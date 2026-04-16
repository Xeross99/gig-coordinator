module HostAdmin
  class BaseController < ApplicationController
    before_action :require_host!
    layout "host_admin"
  end
end
