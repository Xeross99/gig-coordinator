class CampaignParticipationEvent < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :campaign_participation

  enum :event_type, {
    joined:           0,
    cancelled:        1,
    reserved:         2,
    accepted:         3,
    declined:         4,
    promoted:         5,
    expired:          6,
    joined_waitlist:  7
  }
end
