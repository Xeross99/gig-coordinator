module ApplicationHelper
  # Cheap user-agent classifier for the "Urządzenia i sesje" list on the
  # profile page. Covers the platforms we actually see — anything exotic
  # falls through to "Nieznane urządzenie".
  def session_ua_labels(user_agent)
    ua = user_agent.to_s
    os =
      case ua
      when /iPhone/  then "iPhone"
      when /iPad/    then "iPad"
      when /Android/ then "Android"
      when /Macintosh|Mac OS X/ then "Mac"
      when /Windows/ then "Windows"
      when /Linux/   then "Linux"
      else "Nieznane urządzenie"
      end
    browser =
      case ua
      when /Edg\//     then "Edge"
      when /OPR\//     then "Opera"
      when /Firefox\// then "Firefox"
      when /CriOS\//   then "Chrome"
      when /Chrome\//  then "Chrome"
      when /Safari\//  then "Safari"
      end
    [ os, browser ]
  end

  def session_mobile?(user_agent)
    user_agent.to_s.match?(/iPhone|iPad|Android|Mobile/)
  end
end
