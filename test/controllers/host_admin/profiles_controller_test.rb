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
      patch host_profile_path, params: { host: { email: "nie-email" } }
      assert_response :unprocessable_content
    end

    test "PATCH update accepts photo upload" do
      file = Rack::Test::UploadedFile.new(StringIO.new("fake-png"), "image/png", original_filename: "me.png")
      patch host_profile_path, params: { host: { photo: file } }
      assert_redirected_to edit_host_profile_path
      assert hosts(:jan).reload.photo.attached?
    end

    test "GET edit wires the photo-upload Stimulus controller" do
      get edit_host_profile_path
      assert_response :success
      assert_select "form[data-controller~=?][data-photo-upload-url-value=?]", "photo-upload", rails_direct_uploads_path
      assert_select "input[type=file][data-photo-upload-target=input][accept=?]", "image/*"
      assert_select "input[type=hidden][name=?][disabled]", "host[photo]"
      assert_select "button[type=button][data-action=?]", "click->photo-upload#selectFile", text: /Wybierz zdjęcie/
      assert_select "input[type=file][name='host[photo]']", count: 0
    end

    test "PATCH update attaches a photo from a direct-upload signed_id" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("fake-png"), filename: "me.png", content_type: "image/png"
      )
      patch host_profile_path, params: { host: { photo: blob.signed_id } }
      assert_redirected_to edit_host_profile_path
      assert hosts(:jan).reload.photo.attached?
      assert_equal blob.id, hosts(:jan).reload.photo.blob.id
    end
  end
end
