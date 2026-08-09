require "test_helper"

class RankPromotionMailerTest < ActionMailer::TestCase
  test "notify renders recipient, subject and rank-specific description" do
    user = users(:ala)
    mail = RankPromotionMailer.notify(user, new_title: :kurnikowy_komendant)

    title_label = User::TITLE_LABELS["kurnikowy_komendant"]
    assert_equal [ user.email ],                                                  mail.to
    assert_equal "Awans! Masz teraz rangę #{title_label}",                        mail.subject

    text = mail.text_part.decoded
    html = mail.html_part.decoded

    assert_match user.first_name,                                         text
    assert_match title_label,                                             text
    assert_match User::TITLE_DESCRIPTIONS_PERSONAL["kurnikowy_komendant"],    text

    assert_match user.first_name,                                         html
    assert_match title_label,                                             html

    # Rank icon rendered in both parts.
    icon = User::TITLE_ICONS["kurnikowy_komendant"]
    assert_match icon, text
    assert_match icon, html
  end

  test "notify uses a different icon per notifiable rank" do
    user = users(:ala)
    mistrz_html   = RankPromotionMailer.notify(user, new_title: :mistrz_piora).html_part.decoded
    komendant_html = RankPromotionMailer.notify(user, new_title: :kurnikowy_komendant).html_part.decoded

    assert_match    User::TITLE_ICONS["mistrz_piora"],        mistrz_html
    assert_no_match User::TITLE_ICONS["kurnikowy_komendant"], mistrz_html
    assert_match    User::TITLE_ICONS["kurnikowy_komendant"], komendant_html
    assert_no_match User::TITLE_ICONS["mistrz_piora"],        komendant_html
  end

  test "notify picks the description matching the new_title" do
    user = users(:ala)
    mail = RankPromotionMailer.notify(user, new_title: :mistrz_piora)

    text = mail.text_part.decoded
    assert_match User::TITLE_LABELS["mistrz_piora"],                text
    assert_match User::TITLE_DESCRIPTIONS_PERSONAL["mistrz_piora"],     text
    # Leakage guard: description of a different rank must not appear.
    assert_no_match User::TITLE_DESCRIPTIONS_PERSONAL["kurnikowy_komendant"], text
  end

  test "notify accepts a string new_title too" do
    mail = RankPromotionMailer.notify(users(:ala), new_title: "mistrz_piora")
    assert_match User::TITLE_LABELS["mistrz_piora"],              mail.text_part.decoded
    assert_match User::TITLE_DESCRIPTIONS_PERSONAL["mistrz_piora"],   mail.text_part.decoded
  end

  test "notify delivers for every rank above zoltodziob" do
    %i[kurzy_pacholek kurnikowy_gangster kurnikowy_komendant mistrz_piora].each do |title|
      ActionMailer::Base.deliveries.clear
      RankPromotionMailer.notify(users(:ala), new_title: title).deliver_now
      assert_equal 1, ActionMailer::Base.deliveries.size, "#{title} powinien wysłać maila"
    end
  end

  test "notify is a no-op for zoltodziob (ranga startowa)" do
    ActionMailer::Base.deliveries.clear
    RankPromotionMailer.notify(users(:ala), new_title: :zoltodziob).deliver_now
    assert_empty ActionMailer::Base.deliveries
  end

  test "notify is a no-op for an unknown rank string" do
    ActionMailer::Base.deliveries.clear
    RankPromotionMailer.notify(users(:ala), new_title: "nieistniejaca_ranga").deliver_now
    assert_empty ActionMailer::Base.deliveries
  end

  test "notify uses the 2nd-person variant of the description (not the documentation one)" do
    %i[kurzy_pacholek kurnikowy_gangster kurnikowy_komendant mistrz_piora].each do |title|
      mail = RankPromotionMailer.notify(users(:ala), new_title: title)
      personal = User::TITLE_DESCRIPTIONS_PERSONAL.fetch(title.to_s)
      docs     = User::TITLE_DESCRIPTIONS.fetch(title.to_s)

      [ mail.text_part.decoded, mail.html_part.decoded ].each do |body|
        assert_match    personal, body, "mail dla #{title} musi mieć wariant w 2 os."
        assert_no_match docs,     body, "mail dla #{title} NIE powinien używać 3-os. wersji z /informacje"
      end
    end
  end

  test "notify subject zawiera etykietę rangi dla każdego awansu" do
    %i[kurzy_pacholek kurnikowy_gangster kurnikowy_komendant mistrz_piora].each do |title|
      mail = RankPromotionMailer.notify(users(:ala), new_title: title)
      label = User::TITLE_LABELS.fetch(title.to_s)
      assert_equal "Awans! Masz teraz rangę #{label}", mail.subject
    end
  end

  test "notify mail body NIE ma już CTA przycisku ani raw URL do profilu" do
    mail = RankPromotionMailer.notify(users(:ala), new_title: :mistrz_piora)
    [ mail.text_part.decoded, mail.html_part.decoded ].each do |body|
      assert_no_match "Zobacz swój profil", body, "CTA przycisk został usunięty"
      assert_no_match "/profil/edit",                       body, "link do profilu został usunięty"
    end
  end
end
