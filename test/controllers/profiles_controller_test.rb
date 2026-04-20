require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:ala)) }

  test "GET edit wires the photo-upload Stimulus controller to the direct uploads endpoint" do
    get edit_profile_path
    assert_response :success
    assert_select "form[data-controller~=?][data-photo-upload-url-value=?]", "photo-upload", rails_direct_uploads_path
    assert_select "form[data-turbo=?]", "false"
    assert_select "input[type=file][data-photo-upload-target=input][accept=?]", "image/*"
    assert_select "input[type=hidden][name=?][disabled]", "user[photo]"
    assert_select "button[type=button][data-action=?]", "click->photo-upload#selectFile", text: /Wybierz zdjęcie/
  end

  test "PATCH update attaches a photo from a direct-upload signed_id" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-png"),
      filename: "me.png",
      content_type: "image/png"
    )

    patch profile_path, params: { user: { photo: blob.signed_id } }

    assert_redirected_to edit_profile_path
    assert_equal "Zapisano", flash[:notice]
    assert users(:ala).reload.photo.attached?
    assert_equal blob.id, users(:ala).reload.photo.blob.id
  end

  test "PATCH update still accepts a multipart photo upload" do
    file = Rack::Test::UploadedFile.new(StringIO.new("fake-png"), "image/png", original_filename: "me.png")

    patch profile_path, params: { user: { photo: file } }

    assert_redirected_to edit_profile_path
    assert users(:ala).reload.photo.attached?
  end

  test "PATCH update without a photo param leaves the existing attachment intact" do
    users(:ala).photo.attach(
      io: StringIO.new("original"),
      filename: "original.png",
      content_type: "image/png"
    )
    original_blob_id = users(:ala).photo.blob.id

    # The hidden user[photo] input is rendered `disabled` until DirectUpload
    # fills it, so a bare submit sends no `user` param at all. params.expect
    # rejects that with 400 — but the important invariant is that the existing
    # attachment is not wiped.
    patch profile_path, params: { user: {} }

    assert users(:ala).reload.photo.attached?
    assert_equal original_blob_id, users(:ala).reload.photo.blob.id
  end

  test "hosts cannot reach the worker profile edit" do
    sign_in_as(hosts(:jan))
    get edit_profile_path
    assert_redirected_to login_path
  end

  test "PATCH update ignores phone param (admin-managed field)" do
    users(:ala).update!(phone: "111 222 333")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-png"), filename: "me.png", content_type: "image/png"
    )

    patch profile_path, params: { user: { photo: blob.signed_id, phone: "999 999 999" } }

    assert_equal "111 222 333", users(:ala).reload.phone
  end
end
