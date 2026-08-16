module HostAdmin
  class EventCampaignsController < BaseController
    before_action :load_campaign, only: %i[show edit update destroy]

    def index
      @campaigns = Current.host.event_campaigns.order(created_at: :desc)
      campaign_ids = @campaigns.map(&:id)
      @event_counts = Event.where(event_campaign_id: campaign_ids)
                           .group(:event_campaign_id).count
      @slots_taken = CampaignParticipation.holding_slot
                                          .where(event_campaign_id: campaign_ids)
                                          .group(:event_campaign_id).count
    end

    def show
      @upcoming_sub_events = @campaign.upcoming_events
      @past_sub_events     = @campaign.past_events
      @history = CampaignParticipationEvent
        .joins(:campaign_participation)
        .where(campaign_participations: { event_campaign_id: @campaign.id })
        .includes(campaign_participation: { user: { photo_attachment: :blob } })
        .order(created_at: :desc)
    end

    def new
      @campaign = Current.host.event_campaigns.new(capacity: 4)
    end

    def create
      @campaign = Current.host.event_campaigns.new(event_campaign_params)
      if @campaign.save
        redirect_to host_event_campaign_path(@campaign), notice: "Seria zleceń utworzona."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      @campaign.edited_by = nil
      if @campaign.update(event_campaign_params)
        redirect_to host_event_campaign_path(@campaign)
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @campaign.destroy
      redirect_to host_event_campaigns_path
    end

    private

    def load_campaign
      @campaign = Current.host.event_campaigns.find(params[:id])
    end

    def event_campaign_params
      params.require(:event_campaign).permit(:name, :capacity)
    end
  end
end
