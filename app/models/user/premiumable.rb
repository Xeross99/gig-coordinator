module User::Premiumable
  extend ActiveSupport::Concern

  # Player cards = pixel-art profile backgrounds. Key = file name in
  # app/assets/images/player_cards/<key>.svg.
  PLAYER_CARD_LABELS = {
    "traktor"   => "Kury na traktorze",
    "kontener"  => "Kontener pełen kur",
    "wakacje"   => "Wakacyjny luz",
    "ladowarka" => "Kura na ładowarce",
    "kosmos"    => "Kura w kosmosie",
    "kurnik"    => "Kura z gównem"
  }.freeze

  PLAYER_CARDS = PLAYER_CARD_LABELS.keys.freeze
  PREMIUM_DURATION = 1.year

  included do
    normalizes :player_card, with: ->(v) { v.presence }

    validates :player_card, inclusion: { in: PLAYER_CARDS }, allow_nil: true

    before_save :clear_player_card_unless_premium

    after_update_commit :notify_premium_granted
  end

  def premium?
    admin? || premium_active?
  end

  def premium_active?
    premium_until.present? && premium_until.future?
  end

  # Virtual boolean behind the admin checkbox. Ticking grants a year, unticking
  # revokes. Saving the form without changing the box does NOT extend the date
  # (otherwise every „Zapisz" would reset the year).
  def premium
    premium_active?
  end

  def premium=(value)
    active = ActiveModel::Type::Boolean.new.cast(value)
    return if active == premium_active?
    self.premium_until = active ? PREMIUM_DURATION.from_now : nil
  end

  # The only gate for rendering a card. Once premium ends the card disappears
  # right away; the column is cleared on the next save.
  def player_card?
    premium? && player_card.present?
  end

  # Thank-you push on grant or renewal, from any write path (admin checkbox,
  # console). Revoking is silent — hence the premium_active? guard.
  def notify_premium_granted
    return unless saved_change_to_premium_until? && premium_active?

    WebPushNotifier.perform_later(:premium_granted, user_id: id)
  end

  private

  # Invariant: only premium accounts keep a card. The controller already drops
  # player_card from non-premium params; this also covers console and service
  # writes.
  def clear_player_card_unless_premium
    self.player_card = nil unless premium?
  end
end
