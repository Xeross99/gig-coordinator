class PromoteTomaszWisniewskiToKomendant < ActiveRecord::Migration[8.1]
  def up
    user = User.find_by(first_name: "Tomasz", last_name: "Wiśniewski")
    return unless user

    user.update!(title: :kurnikowy_komendant)
    RankPromotionMailer.notify(user, new_title: :kurnikowy_komendant).deliver_later if user.email.present?
  end

  def down
    user = User.find_by(first_name: "Tomasz", last_name: "Wiśniewski")
    return unless user

    user.update!(title: :zoltodziob)
  end
end
