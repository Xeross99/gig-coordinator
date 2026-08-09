class EventCampaignsController < ApplicationController
  before_action :require_user!
  before_action :require_event_creator!, only: %i[new create]
  before_action :require_campaign_manager!, only: %i[edit update destroy]

  def show
    @campaign = EventCampaign.includes(:host, :creator).find(params[:id])
    @upcoming_sub_events = @campaign.upcoming_events
                                    .includes(host: { photo_attachment: :blob })
    @past_sub_events     = @campaign.past_events
                                    .includes(host: { photo_attachment: :blob })
    sub_event_ids = @upcoming_sub_events.map(&:id) + @past_sub_events.map(&:id)
    @my_status_by_event_id = if Current.user
      Current.user.participations
             .where(event_id: sub_event_ids)
             .where.not(status: :cancelled)
             .index_by(&:event_id)
             .transform_values(&:status)
    else
      {}
    end
  end

  def history
    @campaign = EventCampaign.includes(:host, :creator).find(params[:id])
    @entries  = build_history_entries(@campaign)
  end

  def new
    @campaign = EventCampaign.new(capacity: 4)
    @hosts = allowed_hosts.order(:last_name, :first_name)
    @users_for_prereg = users_for_prereg(@campaign)
  end

  def create
    @campaign = EventCampaign.new(event_campaign_params)
    @campaign.creator = Current.user
    unless allowed_hosts.exists?(id: @campaign.host_id)
      redirect_to root_path, alert: Copy::Events::NEW_EVENT_FORBIDDEN and return
    end
    if @campaign.save
      redirect_to event_campaign_path(@campaign), notice: Copy::EventCampaigns::CREATED
    else
      @hosts = allowed_hosts.order(:last_name, :first_name)
      @users_for_prereg = users_for_prereg(@campaign)
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @hosts = allowed_hosts.order(:last_name, :first_name)
    @users_for_prereg = users_for_prereg(@campaign)
  end

  def update
    @campaign.edited_by = Current.user
    if @campaign.update(event_campaign_params)
      redirect_to event_campaign_path(@campaign), notice: "Zmiany zapisane."
    else
      @hosts = allowed_hosts.order(:last_name, :first_name)
      @users_for_prereg = users_for_prereg(@campaign)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @campaign.destroy
    redirect_to root_path, notice: "Seria zleceń usunięta."
  end

  private

  def build_history_entries(campaign)
    entries = [ { at: campaign.created_at, kind: :created, creator: campaign.creator, host: campaign.host } ]

    campaign.campaign_participations
            .includes(:campaign_participation_events, user: { photo_attachment: :blob })
            .each do |p|
      p.campaign_participation_events.each do |pe|
        entries << { at: pe.created_at, kind: :participation_event, participation: p, participation_event: pe }
      end
    end

    campaign.changes_log.includes(:user).each do |c|
      entries << { at: c.created_at, kind: :edited, change: c }
    end
    entries.sort_by { |e| e[:at] }.reverse
  end

  def allowed_hosts
    Current.user.allowed_hosts
  end

  def users_for_prereg(campaign)
    User.available_for_prereg(
      excluding: (campaign.campaign_participations.select(:user_id) if campaign&.persisted?)
    )
  end

  def require_event_creator!
    return if Current.user&.can_create_events?

    redirect_to root_path, alert: Copy::Events::NEW_EVENT_FORBIDDEN
  end

  def require_campaign_manager!
    @campaign = EventCampaign.find(params[:id])
    # Mirror EventsController#require_event_manager!: admin / mistrz_piora /
    # komendant zarządzający tym hostem mogą edytować. Reszta — nie.
    return if Current.user&.admin?
    return if Current.user&.mistrz_piora?
    return if Current.user&.kurnikowy_komendant? && Current.user.managed_hosts.exists?(id: @campaign.host_id)

    redirect_to event_campaign_path(@campaign), alert: Copy::Events::MANAGE_FORBIDDEN
  end

  # Whitelist + przekształcenie nested events_attributes:
  # `event_date`+`start_hour/minute`+`duration_hours/minutes` → `scheduled_at`/`ends_at`
  # (mirror EventsController#event_params transformation). Host_id sub-eventu
  # dziedziczymy z kampanii — w UI nie ma osobnego dropdownu na sub-evencie.
  def event_campaign_params
    permitted = params.require(:event_campaign).permit(
      :name, :host_id, :capacity, :notes,
      pre_registered_user_ids: [],
      events_attributes: %i[
        id _destroy name event_date
        start_hour start_minute
        duration_hours duration_minutes
        pay_per_person capacity
      ]
    )
    attrs = permitted.to_h.with_indifferent_access
    parent_host_id = attrs[:host_id]

    if attrs[:events_attributes].present?
      sub_events = attrs[:events_attributes]
      sub_events = sub_events.values if sub_events.is_a?(Hash)
      attrs[:events_attributes] = sub_events.map { |a| transform_sub_event_attributes(a, parent_host_id) }
    end

    attrs
  end

  def transform_sub_event_attributes(raw_attrs, host_id)
    a = EventSchedule.compose(raw_attrs.with_indifferent_access)
    a[:host_id] = host_id if host_id.present?
    a
  end
end
