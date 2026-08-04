require 'rails_helper'

RSpec.describe Poll, type: :model do
  describe 'associations' do
    it 'belongs to a guild' do
      poll = build(:poll, guild: nil)
      expect(poll).not_to be_valid
    end

    it 'belongs to a creator' do
      poll = build(:poll, creator: nil)
      expect(poll).not_to be_valid
    end

    it 'has many poll_votes' do
      poll = create(:poll)
      vote = create(:poll_vote, poll: poll)
      expect(poll.poll_votes).to include(vote)
    end

    it 'destroys poll_votes when destroyed' do
      poll = create(:poll)
      create(:poll_vote, poll: poll)
      expect { poll.destroy }.to change(PollVote, :count).by(-1)
    end
  end

  describe 'validations' do
    it 'requires title' do
      poll = build(:poll, title: nil)
      expect(poll).not_to be_valid
    end

    it 'validates title length' do
      poll = build(:poll, title: 'a' * 256)
      expect(poll).not_to be_valid
    end

    it 'requires deadline' do
      poll = build(:poll, deadline: nil)
      expect(poll).not_to be_valid
    end
  end

  describe 'scopes' do
    let(:guild) { create(:guild) }
    let(:user) { create(:user) }
    let!(:open_poll) { create(:poll, guild: guild, creator: user, deadline: 1.week.from_now) }
    let!(:closed_poll) { create(:poll, :closed, guild: guild, creator: user) }

    describe '.open' do
      it 'returns only open polls' do
        expect(Poll.open).to include(open_poll)
        expect(Poll.open).not_to include(closed_poll)
      end
    end

    describe '.closed' do
      it 'returns only closed polls' do
        expect(Poll.closed).to include(closed_poll)
        expect(Poll.closed).not_to include(open_poll)
      end
    end

    describe '.ordered' do
      it 'orders polls by created_at descending' do
        expect(Poll.ordered.first).to eq(closed_poll)
      end
    end
  end

  describe '#open?' do
    let(:poll) { create(:poll) }

    context 'when deadline is in the future' do
      it 'returns true' do
        poll.deadline = 1.day.from_now
        expect(poll.open?).to be true
      end
    end

    context 'when deadline is in the past' do
      it 'returns false' do
        poll.deadline = 1.day.ago
        expect(poll.open?).to be false
      end
    end
  end

  describe '#closed?' do
    let(:poll) { create(:poll) }

    context 'when deadline is in the past' do
      it 'returns true' do
        poll.deadline = 1.day.ago
        expect(poll.closed?).to be true
      end
    end

    context 'when deadline is in the future' do
      it 'returns false' do
        poll.deadline = 1.day.from_now
        expect(poll.closed?).to be false
      end
    end
  end

  describe '#vote_counts' do
    let(:poll) { create(:poll) }
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:user3) { create(:user) }

    before do
      create(:poll_vote, poll: poll, user: user1, choice: :yes)
      create(:poll_vote, poll: poll, user: user2, choice: :no)
      create(:poll_vote, poll: poll, user: user3, choice: :maybe)
    end

    it 'returns counts for each choice' do
      expect(poll.vote_counts).to eq({ yes: 1, no: 1, maybe: 1 })
    end
  end

  describe '#total_votes' do
    let(:poll) { create(:poll) }
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    it 'returns the total number of votes' do
      create(:poll_vote, poll: poll, user: user1, choice: :yes)
      create(:poll_vote, poll: poll, user: user2, choice: :no)
      expect(poll.total_votes).to eq(2)
    end

    it 'returns 0 when there are no votes' do
      expect(poll.total_votes).to eq(0)
    end
  end

  describe '#vote_percentages' do
    let(:poll) { create(:poll) }
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:user3) { create(:user) }
    let(:user4) { create(:user) }

    context 'with votes' do
      before do
        create(:poll_vote, poll: poll, user: user1, choice: :yes)
        create(:poll_vote, poll: poll, user: user2, choice: :yes)
        create(:poll_vote, poll: poll, user: user3, choice: :no)
        create(:poll_vote, poll: poll, user: user4, choice: :maybe)
      end

      it 'returns percentages for each choice' do
        percentages = poll.vote_percentages
        expect(percentages[:yes]).to eq(50.0)
        expect(percentages[:no]).to eq(25.0)
        expect(percentages[:maybe]).to eq(25.0)
      end
    end

    context 'without votes' do
      it 'returns 0 for all choices' do
        expect(poll.vote_percentages).to eq({ yes: 0, no: 0, maybe: 0 })
      end
    end
  end

  describe '#user_vote' do
    let(:poll) { create(:poll) }
    let(:user) { create(:user) }

    context 'when user has voted' do
      let!(:vote) { create(:poll_vote, poll: poll, user: user, choice: :yes) }

      it 'returns the user vote' do
        expect(poll.user_vote(user)).to eq(vote)
      end
    end

    context 'when user has not voted' do
      it 'returns nil' do
        expect(poll.user_vote(user)).to be_nil
      end
    end
  end

  describe 'discord_role_mentions' do
    it 'stores role mentions as an array' do
      poll = create(:poll, discord_role_mentions: ["111111111", "222222222"])
      expect(poll.discord_role_mentions).to eq(["111111111", "222222222"])
    end

    it 'defaults to empty array' do
      poll = create(:poll)
      expect(poll.discord_role_mentions || []).to eq([])
    end
  end
end

