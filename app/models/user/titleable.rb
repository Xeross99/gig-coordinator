module User::Titleable
  extend ActiveSupport::Concern

  TITLE_BADGE_COLORS = {
    "rookie"         => "bg-gray-100 text-gray-600",
    "member"     => "bg-green-100 text-green-700",
    "veteran" => "bg-purple-100 text-purple-700",
    "master"       => "bg-yellow-100 text-yellow-800"
  }.freeze

  included do
    enum :title, { rookie: 0, member: 1, veteran: 2, master: 3 }
  end

  def title_badge_classes
    TITLE_BADGE_COLORS.fetch(title, "bg-gray-100 text-gray-600")
  end

  def display_title
    I18n.t("user.titles.#{title}", default: title.to_s.humanize)
  end
end
