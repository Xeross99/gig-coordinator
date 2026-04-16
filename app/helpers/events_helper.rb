module EventsHelper
  def google_maps_embed_src(location)
    "https://maps.google.com/maps?q=#{CGI.escape(location.to_s)}&output=embed"
  end

  def google_maps_open_url(location)
    "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(location.to_s)}"
  end
end
