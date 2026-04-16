class PwaController < ApplicationController
  skip_before_action :load_current_session, only: %i[manifest service_worker]

  def manifest
    render json: {
      name: "GigCoordinator",
      short_name: "GigCoordinator",
      start_url: "/",
      display: "standalone",
      background_color: "#f5f5f4",
      theme_color: "#111111",
      icons: [
        { src: "/icon.png", sizes: "512x512", type: "image/png" }
      ]
    }
  end

  def service_worker
    render plain: "// empty — filled in M9", content_type: "application/javascript"
  end
end
