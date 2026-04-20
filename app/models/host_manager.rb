class HostManager < ApplicationRecord
  belongs_to :user
  belongs_to :host

  validates :user_id, uniqueness: { scope: :host_id }
end
