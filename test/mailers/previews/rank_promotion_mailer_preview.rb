class RankPromotionMailerPreview < ActionMailer::Preview
  def komendant
    RankPromotionMailer.notify(sample_user, new_title: :captain)
  end

  def master
    RankPromotionMailer.notify(sample_user, new_title: :master)
  end

  private

  def sample_user
    User.first || User.new(first_name: "Podgląd", last_name: "User", email: "preview@example.com")
  end
end
