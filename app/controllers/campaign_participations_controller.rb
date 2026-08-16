class CampaignParticipationsController < ApplicationController
  before_action :load_campaign

  # POST /kampanie/:event_campaign_id/uczestnictwo
  # Standardowy zapis się NIE pojawia jako self-service: primary roster buduje
  # tylko twórca kampanii (przez pre_registered_user_ids w formularzu) lub
  # mistrz_piora przyjmując auto-rezerwację. Zostawiamy endpoint dostępny tylko
  # dla zwykłych userów którzy chcieliby się sami zapisać — gating w ParticipationsController
  # nie pasuje bo na sub-eventach mają inną semantykę. Tu — tylko reaktywacja
  # cancelled (ktoś wcześniej był w primary, się wypisał, chce wrócić).
  def create
    if Current.user.blocked_from?(@campaign.host)
      redirect_to event_campaign_path(@campaign), alert: "Masz blokadę u tego gospodarza - nie możesz zapisać się na to zlecenie." and return
    end

    result = nil
    EventCampaign.transaction do
      @campaign.lock!
      existing = @campaign.campaign_participations.find_by(user_id: Current.user.id)
      if existing.nil?
        status, position = next_slot_for(@campaign)
        @campaign.campaign_participations.create!(user: Current.user, status: status, position: position)
        result = status
      elsif existing.cancelled? || (existing.reserved? && existing.reservation_expired?)
        status, position = next_slot_for(@campaign)
        existing.update!(status: status, position: position, reserved_until: nil)
        result = status
      end
    end

    flash[:confetti] = true if result == :confirmed
    redirect_to event_campaign_path(@campaign)
  end

  # DELETE /kampanie/:event_campaign_id/uczestnictwo
  # Promocja z waitlisty primary + resequence + kaskada na sub-eventy dzieją
  # się w modelu (CampaignParticipation#cascade_cancellation) — jedna ścieżka
  # dla kontrolera, API i konsoli.
  def destroy
    EventCampaign.transaction do
      @campaign.lock!
      cp = @campaign.campaign_participations.active.find_by(user_id: Current.user.id)
      cp&.update!(status: :cancelled, reserved_until: nil)
    end

    redirect_to event_campaign_path(@campaign)
  end

  # POST /kampanie/:event_campaign_id/uczestnictwo/accept
  # Mistrz Pióra akceptuje auto-rezerwację primary rostera (2.5h). reserved → confirmed.
  def accept
    result = nil
    EventCampaign.transaction do
      @campaign.lock!
      cp = @campaign.campaign_participations.reserved.find_by(user_id: Current.user.id)
      if cp && !cp.reservation_expired?
        if @campaign.campaign_participations.confirmed.count < @campaign.capacity
          pos = (@campaign.campaign_participations.confirmed.maximum(:position) || 0) + 1
          cp.update!(status: :confirmed, position: pos, reserved_until: nil)
          result = :confirmed
        else
          pos = (@campaign.campaign_participations.waitlist.maximum(:position) || 0) + 1
          cp.update!(status: :waitlist, position: pos, reserved_until: nil)
          result = :waitlist
        end
      end
    end

    flash[:confetti] = true if result == :confirmed
    notice = case result
    when :confirmed then "Potwierdzone — jesteś w primary rosterze kampanii."
    when :waitlist  then "Primary roster jest pełny — jesteś na liście rezerwowej kampanii."
    end
    redirect_to event_campaign_path(@campaign), notice: notice
  end

  # POST /kampanie/:event_campaign_id/uczestnictwo/decline
  # Mistrz odrzuca rezerwację — slot zwalnia się dla kolejnego mistrza/waitlist.
  # refill_one + resequence + kaskada robi model (reserved→cancelled).
  def decline
    EventCampaign.transaction do
      @campaign.lock!
      cp = @campaign.campaign_participations.reserved.find_by(user_id: Current.user.id)
      cp&.update!(status: :cancelled, reserved_until: nil)
    end
    redirect_to event_campaign_path(@campaign), notice: "Odrzucone. Slot idzie do kolejnej osoby z rankingu."
  end

  private

  def load_campaign
    @campaign = EventCampaign.find(params[:event_campaign_id])
  end

  def next_slot_for(campaign)
    if campaign.slots_taken < campaign.capacity
      [ :confirmed, (campaign.campaign_participations.confirmed.maximum(:position) || 0) + 1 ]
    else
      [ :waitlist,  (campaign.campaign_participations.waitlist.maximum(:position)  || 0) + 1 ]
    end
  end
end
