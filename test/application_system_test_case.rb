require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include SystemAuthHelpers
  driven_by :selenium, using: :chrome, screen_size: [ 390, 844 ]
end
