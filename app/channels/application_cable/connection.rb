module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_session

    def connect
      self.current_session = find_verified_session
    end

    private

    def find_verified_session
      token = request.params[:token] || cookies.signed[:session_token]
      if token.present?
        Session.find_by(token: token) || reject_unauthorized_connection
      else
        reject_unauthorized_connection
      end
    end
  end
end
