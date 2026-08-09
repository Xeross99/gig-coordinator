require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include SystemAuthHelpers
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]
end
