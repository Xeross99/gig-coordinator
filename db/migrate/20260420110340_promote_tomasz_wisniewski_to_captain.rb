class PromoteTomaszWisniewskiToKomendant < ActiveRecord::Migration[8.1]
  def up
    user = User.find_by(first_name: "Michał", last_name: "Wiśniewski")
    return unless user

    user.update!(title: :captain)
    RankPromotionMailer.notify(user, new_title: :captain).deliver_later if user.email.present?
  end

  def down
    user = User.find_by(first_name: "Michał", last_name: "Wiśniewski")
    return unless user

    user.update!(title: :rookie)
  end
end
