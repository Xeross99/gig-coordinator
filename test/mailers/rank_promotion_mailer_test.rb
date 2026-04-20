require "test_helper"

class RankPromotionMailerTest < ActionMailer::TestCase
  test "notify renders recipient, subject and rank-specific description" do
    user = users(:ala)
    mail = RankPromotionMailer.notify(user, new_title: :captain)

    title_label = I18n.t("user.titles.captain")
    assert_equal [ user.email ],                                                  mail.to
    assert_equal I18n.t("mailers.rank_promotion.subject", title: title_label),    mail.subject

    text = mail.text_part.decoded
    html = mail.html_part.decoded

    assert_match user.first_name,                                         text
    assert_match title_label,                                             text
    assert_match I18n.t("user.rank_descriptions.captain"),    text

    assert_match user.first_name,                                         html
    assert_match title_label,                                             html
    assert_match "/profil/edit",                                          html

    # Rank icon rendered in both parts.
    icon = I18n.t("user.rank_icons.captain")
    assert_match icon, text
    assert_match icon, html
  end

  test "notify uses a different icon per notifiable rank" do
    user = users(:ala)
    mistrz_html   = RankPromotionMailer.notify(user, new_title: :master).html_part.decoded
    komendant_html = RankPromotionMailer.notify(user, new_title: :captain).html_part.decoded

    assert_match    I18n.t("user.rank_icons.master"),        mistrz_html
    assert_no_match I18n.t("user.rank_icons.captain"), mistrz_html
    assert_match    I18n.t("user.rank_icons.captain"), komendant_html
    assert_no_match I18n.t("user.rank_icons.master"),        komendant_html
  end

  test "notify picks the description matching the new_title" do
    user = users(:ala)
    mail = RankPromotionMailer.notify(user, new_title: :master)

    text = mail.text_part.decoded
    assert_match I18n.t("user.titles.master"),                text
    assert_match I18n.t("user.rank_descriptions.master"),     text
    # Leakage guard: description of a different rank must not appear.
    assert_no_match I18n.t("user.rank_descriptions.captain"), text
  end

  test "notify accepts a string new_title too" do
    mail = RankPromotionMailer.notify(users(:ala), new_title: "master")
    assert_match I18n.t("user.titles.master"),              mail.text_part.decoded
    assert_match I18n.t("user.rank_descriptions.master"),   mail.text_part.decoded
  end

  test "notify is a no-op for lower ranks (no mail delivered)" do
    %i[rookie member veteran].each do |low_title|
      ActionMailer::Base.deliveries.clear
      RankPromotionMailer.notify(users(:ala), new_title: low_title).deliver_now
      assert_empty ActionMailer::Base.deliveries, "#{low_title} nie powinien wysłać żadnego maila"
    end
  end

  test "notify delivers for both notifiable ranks" do
    %i[captain master].each do |title|
      ActionMailer::Base.deliveries.clear
      RankPromotionMailer.notify(users(:ala), new_title: title).deliver_now
      assert_equal 1, ActionMailer::Base.deliveries.size, "#{title} powinien wysłać maila"
    end
  end
end
