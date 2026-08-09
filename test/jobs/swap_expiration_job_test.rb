require "test_helper"

class SwapExpirationJobTest < ActiveJob::TestCase
  setup do
    @event    = events(:chickens_tomorrow)
    @proposer = users(:ala)
    @target   = users(:bartek)
    Participation.create!(event: @event, user: @target,   status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @proposer, status: :waitlist,  position: 1)
  end

  def create_proposal(expires_at:)
    SwapProposal.create!(
      event: @event, proposer: @proposer, target: @target, expires_at: expires_at
    )
  end

  test "expires a pending proposal whose expires_at is in the past" do
    proposal = create_proposal(expires_at: 1.hour.from_now)
    proposal.update_column(:expires_at, 1.minute.ago)

    SwapExpirationJob.new.perform(swap_proposal_id: proposal.id)

    assert proposal.reload.expired?
  end

  test "no-op when proposal was already accepted" do
    proposal = create_proposal(expires_at: 1.hour.from_now)
    proposal.update!(status: :accepted)
    proposal.update_column(:expires_at, 1.minute.ago)

    SwapExpirationJob.new.perform(swap_proposal_id: proposal.id)

    assert proposal.reload.accepted?
  end

  test "no-op when proposal was already declined" do
    proposal = create_proposal(expires_at: 1.hour.from_now)
    proposal.update!(status: :declined)
    proposal.update_column(:expires_at, 1.minute.ago)

    SwapExpirationJob.new.perform(swap_proposal_id: proposal.id)

    assert proposal.reload.declined?
  end

  test "no-op when expires_at is still in the future" do
    proposal = create_proposal(expires_at: 1.hour.from_now)

    SwapExpirationJob.new.perform(swap_proposal_id: proposal.id)

    assert proposal.reload.pending?
  end

  test "no-op (no raise) when proposal has been deleted" do
    proposal = create_proposal(expires_at: 1.hour.from_now)
    id = proposal.id
    proposal.destroy

    assert_nothing_raised do
      SwapExpirationJob.new.perform(swap_proposal_id: id)
    end
  end
end
