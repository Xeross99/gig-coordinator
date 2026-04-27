class MessagesController < ApplicationController
  before_action :require_user!

  # Rate limit — 20 wiadomości / minutę per user. Licznik siedzi w Rails.cache
  # (u nas solid_cache, czyli SQLite), więc działa cross-process na wielu
  # procesach Puma. Hosty + anonimowi (których tu nie ma, ale na wszelki wypadek)
  # fallbackują na IP.
  rate_limit to: 20, within: 1.minute,
             by: -> { Current.user&.id || request.remote_ip },
             with: -> { render_rate_limited },
             only: :create

  # POST /eventy/:event_id/czat/wiadomosci
  def create
    @event   = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    @message = @event.messages.build(user: Current.user, body: params.dig(:message, :body))

    if @message.save
      # Nowa wiadomość dosila czat broadcastem w Message#after_create_commit.
      # Na sukces NIE wymieniamy DOM-u formularza — `chat-form` controller
      # czyści edytor po stronie klienta przez `editor.value = ""`. Dzięki
      # temu na iOS klawiatura nie chowa się po wysłaniu (zachowany focus).
      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to event_chat_path(@event) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            ActionView::RecordIdentifier.dom_id(@event, :chat_form),
            partial: "chats/form",
            locals:  { event: @event, message: @message, autofocus: true }
          ), status: :unprocessable_content
        end
        format.html { redirect_to event_chat_path(@event), alert: @message.errors.full_messages.first }
      end
    end
  end

  private

  def render_rate_limited
    @event   = Event.find(params[:event_id])
    @message = @event.messages.build(user: Current.user, body: params.dig(:message, :body))
    @message.errors.add(:base, I18n.t("participations.rate_limited", default: "Za dużo wiadomości - zwolnij i spróbuj za chwilę."))
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(@event, :chat_form),
          partial: "chats/form",
          locals:  { event: @event, message: @message, autofocus: true }
        ), status: :too_many_requests
      end
      format.html { redirect_to event_chat_path(@event), alert: @message.errors.full_messages.first }
    end
  end
end
