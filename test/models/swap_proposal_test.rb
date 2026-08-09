require "test_helper"

class SwapProposalTest < ActiveSupport::TestCase
  setup do
    @event    = events(:chickens_tomorrow)
    @proposer = users(:ala)
    @target   = users(:bartek)
    Participation.create!(event: @event, user: @target,   status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @proposer, status: :waitlist,  position: 1)
  end

  def build_proposal(**overrides)
    SwapProposal.new(
      {
        event:      @event,
        proposer:   @proposer,
        target:     @target,
        expires_at: SwapProposal::EXPIRATION_WINDOW.from_now
      }.merge(overrides)
    )
  end

  test "happy path: waitlister proposes a swap to a confirmed user" do
    proposal = build_proposal
    assert proposal.valid?, proposal.errors.full_messages.inspect
    assert proposal.save
    assert proposal.pending?
  end

  test "invalid when proposer has no participation on the event" do
    proposal = build_proposal(proposer: users(:cezary))
    refute proposal.valid?
    assert proposal.errors[:proposer].any?
  end

  test "invalid when proposer is confirmed instead of waitlisted" do
    Participation.where(event: @event, user: @proposer)
                 .update_all(status: Participation.statuses[:confirmed], position: 2)
    proposal = build_proposal
    refute proposal.valid?
    assert proposal.errors[:proposer].any?
  end

  test "invalid when proposer's participation is cancelled" do
    Participation.where(event: @event, user: @proposer)
                 .update_all(status: Participation.statuses[:cancelled])
    proposal = build_proposal
    refute proposal.valid?
    assert proposal.errors[:proposer].any?
  end

  test "invalid when target has no participation on the event" do
    proposal = build_proposal(target: users(:cezary))
    refute proposal.valid?
    assert proposal.errors[:target].any?
  end

  test "invalid when target is on the waitlist instead of confirmed" do
    Participation.create!(event: @event, user: users(:dominika), status: :waitlist, position: 2)
    proposal = build_proposal(target: users(:dominika))
    refute proposal.valid?
    assert proposal.errors[:target].any?
  end

  test "second pending proposal for the same (event, proposer, target) is invalid" do
    build_proposal.save!
    dup = build_proposal
    refute dup.valid?
    assert dup.errors[:proposer_id].any?
  end

  test "a declined proposal does not block a fresh pending one for the same pair" do
    first = build_proposal
    first.save!
    first.update!(status: :declined)

    assert build_proposal.valid?
  end

  test "proposer cannot target himself" do
    proposal = build_proposal(target: @proposer)
    refute proposal.valid?
    assert proposal.errors[:target].any? { |m| m.include?("same as proposer") }
  end
end
