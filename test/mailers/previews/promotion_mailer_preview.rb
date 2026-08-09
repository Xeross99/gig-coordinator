class PromotionMailerPreview < ActionMailer::Preview
  def notify
    participation = Participation.confirmed.first ||
                    Participation.new(user: User.first, event: Event.first, status: :confirmed, position: 1)
    PromotionMailer.with(participation: participation).notify
  end
end
