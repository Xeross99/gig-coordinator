class RankPromotionMailer < ApplicationMailer
  # Awans dostaje własnego maila tylko na dwie najwyższe rangi — niższe to część
  # normalnego cyklu życia pracownika i nie zasługują na dedykowaną notyfikację.
  NOTIFIABLE_TITLES = %w[captain master].freeze

  def notify(user, new_title:)
    new_title_s = new_title.to_s
    return unless NOTIFIABLE_TITLES.include?(new_title_s)

    @user         = user
    @new_title    = new_title_s
    @title_label  = I18n.t("user.titles.#{@new_title}")
    @description  = I18n.t("user.rank_descriptions.#{@new_title}")
    @icon         = I18n.t("user.rank_icons.#{@new_title}")
    @profile_url  = edit_profile_url

    mail to: @user.email, subject: I18n.t("mailers.rank_promotion.subject", title: @title_label)
  end
end
