class RankPromotionMailer < ApplicationMailer
  # Every rank-up gets its own mail, lower ranks included. Whether a title change
  # counts as a promotion is decided by `User#send_rank_promotion_email` — this
  # mailer only renders. The one hard rule lives here: zoltodziob is the starting
  # rank, so nobody is ever congratulated on reaching it, not even from a manual
  # console call.
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
