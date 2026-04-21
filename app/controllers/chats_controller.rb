class ChatsController < ApplicationController
  before_action :require_user!

  PAGE_SIZE = 30

  # GET /eventy/:event_id/czat
  # Renderuje zawartość turbo-frame'a czatu. Event show page dokleja ten
  # frame lazy, więc zapytanie leci dopiero gdy user otwiera event. Z param
  # `before=<id>` zwraca turbo_stream z prependem starszych wiadomości —
  # używane przez Stimulus kontroler do infinite-scroll w górę.
  def show
    @event = Event.find(params[:event_id])

    scope = @event.messages.includes(user: { photo_attachment: :blob })
                          .reorder(created_at: :desc, id: :desc)
    if params[:before].present?
      scope = scope.where("messages.id < ?", params[:before].to_i)
    end
    window = scope.limit(PAGE_SIZE).to_a

    @messages = window.reverse
    @has_more = window.size == PAGE_SIZE &&
                @event.messages.where("messages.id < ?", window.last&.id || 0).exists?
    @message  = Message.new

    if params[:before].present?
      render :more, layout: false
    end
  end
end
