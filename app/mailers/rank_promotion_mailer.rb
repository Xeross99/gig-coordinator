class RankPromotionMailer < ApplicationMailer
  def notify(user, new_title:)
    return unless User.titles.key?(new_title.to_s)
    return if new_title.to_s == "zoltodziob"

    @user         = user
    @new_title    = new_title.to_s
    @title_label  = User::TITLE_LABELS.fetch(@new_title)
    @description  = User::TITLE_DESCRIPTIONS_PERSONAL.fetch(@new_title)
    @icon         = User::TITLE_ICONS.fetch(@new_title)
    @profile_url  = edit_profile_url

    mail to: @user.email, subject: "Awans! Masz teraz rangę #{@title_label}"
  end
end
