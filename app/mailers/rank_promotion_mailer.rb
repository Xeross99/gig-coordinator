class RankPromotionMailer < ApplicationMailer
  # Każdy awans (każda zmiana title w górę) wysyła własnego maila — łącznie ze
  # zmianami między niższymi rangami. Decyzja „awans czy degradacja" leży po
  # stronie callbacku w `User#send_rank_promotion_email`, mailer tylko renderuje.
  # Wyjątek: zoltodziob to ranga startowa — nigdy nie wysyłamy „gratulacje, jesteś
  # żółtodziobem" (nawet gdyby ktoś ręcznie wywołał notify z konsoli).
  def notify(user, new_title:)
    new_title_s = new_title.to_s
    return unless User.titles.key?(new_title_s)
    return if new_title_s == "zoltodziob"
    return if recipient_disabled?(user)

    @user         = user
    @new_title    = new_title_s
    @title_label  = User::TITLE_LABELS.fetch(@new_title)
    # Wersja w 2 os. — mail jest skierowany do konkretnej osoby, nie do
    # czytelnika dokumentacji. Strona /informacje używa `rank_descriptions`
    # (3 os.).
    @description  = User::TITLE_DESCRIPTIONS_PERSONAL.fetch(@new_title)
    @icon         = User::TITLE_ICONS.fetch(@new_title)
    @profile_url  = edit_profile_url

    mail to: @user.email, subject: "Awans! Masz teraz rangę #{@title_label}"
  end
end
