module HostAdmin
  class ProfilesController < BaseController
    def edit
      @host = current_host
    end

    def update
      @host = current_host
      if @host.update(profile_params)
        redirect_to edit_host_profile_path, notice: "Zapisano"
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def profile_params
      params.expect(host: %i[first_name last_name email location lat lng photo])
    end
  end
end
