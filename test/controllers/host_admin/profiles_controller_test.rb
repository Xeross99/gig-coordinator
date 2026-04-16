require "test_helper"

module HostAdmin
  class ProfilesControllerTest < ActionDispatch::IntegrationTest
    setup { sign_in_as(hosts(:jan)) }

    test "GET edit renders form with current attributes" do
      get edit_host_profile_path
      assert_response :success
      assert_select "input[name='host[first_name]'][value=?]", "Jan"
    end

    test "PATCH update with valid attributes updates host" do
      patch host_profile_path, params: { host: { first_name: "Janusz", location: "Gdańsk" } }
      assert_redirected_to edit_host_profile_path
      assert_equal "Janusz", hosts(:jan).reload.first_name
      assert_equal "Gdańsk", hosts(:jan).reload.location
    end

    test "PATCH update invalid re-renders edit" do
      patch host_profile_path, params: { host: { email: "" } }
      assert_response :unprocessable_content
    end

    test "PATCH update accepts photo upload" do
      file = Rack::Test::UploadedFile.new(StringIO.new("fake-png"), "image/png", original_filename: "me.png")
      patch host_profile_path, params: { host: { photo: file } }
      assert_redirected_to edit_host_profile_path
      assert hosts(:jan).reload.photo.attached?
    end
  end
end
