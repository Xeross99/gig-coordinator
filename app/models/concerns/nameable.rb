# Host and User are separate models, but both describe a person with a first
# and last name, and both render that name the same way in the UI.
module Nameable
  extend ActiveSupport::Concern

  def display_name
    "#{first_name} #{last_name}"
  end
end
