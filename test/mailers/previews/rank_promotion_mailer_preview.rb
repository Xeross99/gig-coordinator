class RankPromotionMailerPreview < ActionMailer::Preview
  # Brak podglądu dla `zoltodziob` — to ranga startowa, nigdy nie wysyłamy
  # za nią maila (mailer ją odrzuca, callback w User też).

  def kurzy_pacholek
    RankPromotionMailer.notify(sample_user, new_title: :kurzy_pacholek)
  end

  def kurnikowy_gangster
    RankPromotionMailer.notify(sample_user, new_title: :kurnikowy_gangster)
  end

  def kurnikowy_komendant
    RankPromotionMailer.notify(sample_user, new_title: :kurnikowy_komendant)
  end

  def mistrz_piora
    RankPromotionMailer.notify(sample_user, new_title: :mistrz_piora)
  end

  private

  def sample_user
    User.first || User.new(first_name: "Podgląd", last_name: "User", email: "preview@example.com")
  end
end
