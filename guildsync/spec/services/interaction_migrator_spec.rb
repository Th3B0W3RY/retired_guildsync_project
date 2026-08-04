require "rails_helper"

RSpec.describe InteractionMigrator, type: :service do
  let(:user) { create(:user) }
  let(:discord_user_id) { "999888777" }
  let(:migrator) { described_class.new(user: user, discord_user_id: discord_user_id) }

  describe "#migrate_all!" do
    context "with discord-only poll votes" do
      let(:poll) { create(:poll) }
      let!(:discord_vote) { PollVote.create!(poll: poll, discord_user_id: discord_user_id, discord_username: "discorduser", choice: :yes) }

      it "assigns user_id and clears discord fields" do
        migrator.migrate_all!
        discord_vote.reload
        expect(discord_vote.user_id).to eq(user.id)
        expect(discord_vote.discord_user_id).to be_nil
        expect(discord_vote.discord_username).to be_nil
      end
    end

    context "with discord-only event participation" do
      let(:event) { create(:event) }
      let!(:participation) { EventParticipation.create!(event: event, discord_user_id: discord_user_id, discord_username: "discorduser", status: :attending) }

      it "assigns user_id and clears discord fields" do
        migrator.migrate_all!
        participation.reload
        expect(participation.user_id).to eq(user.id)
        expect(participation.discord_user_id).to be_nil
      end
    end

    context "when user already has a vote on the same poll" do
      let(:poll) { create(:poll) }
      let!(:user_vote) { create(:poll_vote, poll: poll, user: user, choice: :no) }
      let!(:discord_vote) { PollVote.create!(poll: poll, discord_user_id: discord_user_id, discord_username: "discorduser", choice: :yes) }

      it "destroys the discord-only vote to avoid conflict" do
        expect { migrator.migrate_all! }.to change(PollVote, :count).by(-1)
        expect(PollVote.exists?(discord_vote.id)).to be false
        expect(PollVote.exists?(user_vote.id)).to be true
      end
    end

    context "wraps everything in a transaction" do
      let(:poll) { create(:poll) }
      let!(:discord_vote) { PollVote.create!(poll: poll, discord_user_id: discord_user_id, discord_username: "discorduser", choice: :yes) }

      it "rolls back all changes if any migration fails" do
        allow_any_instance_of(EventParticipation).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
        event = create(:event)
        EventParticipation.create!(event: event, discord_user_id: discord_user_id, discord_username: "discorduser", status: :attending)

        expect { migrator.migrate_all! rescue nil }.not_to change { discord_vote.reload.user_id }
      end
    end
  end
end
