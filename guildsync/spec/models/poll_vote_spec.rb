require 'rails_helper'

RSpec.describe PollVote, type: :model do
  describe 'associations' do
    it 'belongs to a poll' do
      vote = build(:poll_vote, poll: nil)
      expect(vote).not_to be_valid
    end

    it 'optionally belongs to a user' do
      vote = build(:poll_vote, user: nil, discord_user_id: "12345", discord_username: "test")
      expect(vote).to be_valid
    end
  end

  describe 'validations' do
    it 'requires choice' do
      vote = build(:poll_vote)
      vote.choice = nil
      expect(vote).not_to be_valid
    end

    it 'requires either user_id or discord_user_id' do
      vote = build(:poll_vote, user: nil, discord_user_id: nil)
      expect(vote).not_to be_valid
      expect(vote.errors[:base]).to be_present
    end

    describe 'uniqueness of user per poll' do
      let(:poll) { create(:poll) }
      let(:user) { create(:user) }
      let!(:existing_vote) { create(:poll_vote, poll: poll, user: user, choice: :yes) }

      it 'prevents duplicate votes from same user on same poll' do
        duplicate_vote = build(:poll_vote, poll: poll, user: user, choice: :no)
        expect(duplicate_vote).not_to be_valid
        expect(duplicate_vote.errors[:user_id]).to include("You can only vote once per poll")
      end

      it 'allows same user to vote on different polls' do
        other_poll = create(:poll)
        other_vote = build(:poll_vote, poll: other_poll, user: user, choice: :yes)
        expect(other_vote).to be_valid
      end
    end

    describe 'uniqueness of discord_user_id per poll' do
      let(:poll) { create(:poll) }
      let!(:discord_vote) { PollVote.create!(poll: poll, discord_user_id: "99999", discord_username: "testuser", choice: :yes) }

      it 'prevents duplicate discord votes on same poll' do
        duplicate = PollVote.new(poll: poll, discord_user_id: "99999", discord_username: "testuser", choice: :no)
        expect(duplicate).not_to be_valid
      end

      it 'allows same discord user to vote on different polls' do
        other_poll = create(:poll)
        other_vote = PollVote.new(poll: other_poll, discord_user_id: "99999", discord_username: "testuser", choice: :yes)
        expect(other_vote).to be_valid
      end
    end
  end

  describe 'enum' do
    it 'defines choice enum with yes, no, maybe' do
      expect(PollVote.choices).to eq({ "yes" => 0, "no" => 1, "maybe" => 2 })
    end
  end

  describe 'choice values' do
    let(:poll_vote) { build(:poll_vote) }

    it 'accepts :yes as a valid choice' do
      poll_vote.choice = :yes
      expect(poll_vote).to be_valid
    end

    it 'accepts :no as a valid choice' do
      poll_vote.choice = :no
      expect(poll_vote).to be_valid
    end

    it 'accepts :maybe as a valid choice' do
      poll_vote.choice = :maybe
      expect(poll_vote).to be_valid
    end
  end
end

