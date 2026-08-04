# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlliancePoll, type: :model do
  let(:guild)    { create(:guild) }
  let(:alliance) { create(:alliance, leader_guild: guild, leader_user: guild.owner) }
  let(:user)     { create(:user) }
  let(:poll)     { create(:alliance_poll, alliance: alliance, creator: user) }

  describe "validations" do
    it "requires a title" do
      poll.title = nil
      expect(poll).not_to be_valid
    end

    it "requires a deadline" do
      poll.deadline = nil
      expect(poll).not_to be_valid
    end
  end

  describe "#open? and #closed?" do
    it "is open when deadline is in the future" do
      poll.deadline = 1.hour.from_now
      expect(poll.open?).to be true
      expect(poll.closed?).to be false
    end

    it "is closed when deadline has passed" do
      poll.deadline = 1.hour.ago
      expect(poll.open?).to be false
      expect(poll.closed?).to be true
    end
  end

  describe "#vote_counts" do
    it "returns zero counts when no votes" do
      expect(poll.vote_counts).to eq(yes: 0, no: 0, maybe: 0)
    end

    it "counts votes correctly" do
      user2 = create(:user)
      poll.alliance_poll_votes.create!(user: user,  choice: :yes)
      poll.alliance_poll_votes.create!(user: user2, choice: :no)
      counts = poll.vote_counts
      expect(counts[:yes]).to eq(1)
      expect(counts[:no]).to  eq(1)
      expect(counts[:maybe]).to eq(0)
    end
  end

  describe "#vote_percentages" do
    it "returns all zeros when no votes" do
      expect(poll.vote_percentages).to eq(yes: 0, no: 0, maybe: 0)
    end
  end

  describe "#voters_display_names_by_choice" do
    it "returns empty lists for anonymous polls even when votes exist" do
      poll.update!(anonymous: true)
      other = create(:user)
      poll.alliance_poll_votes.create!(user: user, choice: :yes)
      poll.alliance_poll_votes.create!(user: other, choice: :no)
      expect(poll.voters_display_names_by_choice).to eq(yes: [], no: [], maybe: [])
    end

    it "returns sorted display names per choice when not anonymous" do
      z_user = create(:user, username: "Zed")
      a_user = create(:user, username: "Ann")
      poll.alliance_poll_votes.create!(user: a_user, choice: :yes)
      poll.alliance_poll_votes.create!(user: z_user, choice: :yes)
      poll.alliance_poll_votes.create!(user: user, choice: :maybe)
      names = poll.voters_display_names_by_choice
      expect(names[:yes]).to eq(%w[Ann Zed])
      expect(names[:no]).to eq([])
      expect(names[:maybe]).to eq([ user.name_for_discord_embed ])
    end
  end

  describe "#user_vote" do
    it "returns nil when user has not voted" do
      expect(poll.user_vote(user)).to be_nil
    end

    it "returns the vote when user has voted" do
      vote = poll.alliance_poll_votes.create!(user: user, choice: :yes)
      expect(poll.user_vote(user)).to eq(vote)
    end
  end
end
