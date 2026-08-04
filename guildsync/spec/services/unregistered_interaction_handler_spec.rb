require "rails_helper"

RSpec.describe UnregisteredInteractionHandler, type: :service do
  let(:discord_user_id) { "123456789" }
  let(:discord_username) { "testuser" }
  let(:handler) { described_class.new(discord_user_id: discord_user_id, discord_username: discord_username) }

  describe "#resolve_user" do
    context "when a UserDiscordConnection exists" do
      let(:user) { create(:user) }
      let!(:connection) { user.create_user_discord_connection!(discord_user_id: discord_user_id, access_token: "tok", scopes: "identify") }

      it "returns the associated user" do
        expect(handler.resolve_user).to eq(user)
      end
    end

    context "when no UserDiscordConnection exists" do
      it "returns nil" do
        expect(handler.resolve_user).to be_nil
      end
    end
  end

  describe "#registered?" do
    it "returns true when user is found" do
      user = create(:user)
      user.create_user_discord_connection!(discord_user_id: discord_user_id, access_token: "tok", scopes: "identify")
      expect(handler.registered?).to be true
    end

    it "returns false when user is not found" do
      expect(handler.registered?).to be false
    end
  end

  describe "#find_existing_interaction" do
    let(:poll) { create(:poll) }

    context "when registered user has an existing vote" do
      let(:user) { create(:user) }
      let!(:connection) { user.create_user_discord_connection!(discord_user_id: discord_user_id, access_token: "tok", scopes: "identify") }
      let!(:vote) { create(:poll_vote, poll: poll, user: user, choice: :yes) }

      it "finds the vote by user_id" do
        result = handler.find_existing_interaction(poll.poll_votes)
        expect(result).to eq(vote)
      end
    end

    context "when unregistered user has a discord-only vote" do
      let!(:vote) { PollVote.create!(poll: poll, discord_user_id: discord_user_id, discord_username: discord_username, choice: :yes) }

      it "finds the vote by discord_user_id" do
        result = handler.find_existing_interaction(poll.poll_votes)
        expect(result).to eq(vote)
      end
    end

    context "when no existing interaction" do
      it "returns nil" do
        result = handler.find_existing_interaction(poll.poll_votes)
        expect(result).to be_nil
      end
    end
  end

  describe "#assign_identity" do
    let(:poll) { create(:poll) }

    context "when user is registered" do
      let(:user) { create(:user) }
      let!(:connection) { user.create_user_discord_connection!(discord_user_id: discord_user_id, access_token: "tok", scopes: "identify") }

      it "assigns user and clears discord fields" do
        vote = poll.poll_votes.new(choice: :yes)
        handler.assign_identity(vote)
        expect(vote.user).to eq(user)
        expect(vote.discord_user_id).to be_nil
        expect(vote.discord_username).to be_nil
      end
    end

    context "when user is unregistered" do
      it "assigns discord fields" do
        vote = poll.poll_votes.new(choice: :yes)
        handler.assign_identity(vote)
        expect(vote.user).to be_nil
        expect(vote.discord_user_id).to eq(discord_user_id)
        expect(vote.discord_username).to eq(discord_username)
      end
    end
  end

  describe "#send_onboarding_dm_if_needed" do
    let(:guild) { create(:guild) }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("fake-token")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("GUILDSYNC_BASE_URL", anything).and_return("https://guild-sync.net")
    end

    context "when user is registered" do
      let(:user) { create(:user) }
      let!(:connection) { user.create_user_discord_connection!(discord_user_id: discord_user_id, access_token: "tok", scopes: "identify") }

      it "does not send a DM" do
        expect(DiscordService).not_to receive(:new)
        handler.send_onboarding_dm_if_needed(context_type: "Guild", context_id: guild.id)
      end
    end

    context "when DM already sent for this context" do
      before do
        DiscordOnboardingDm.record_sent!(discord_user_id: discord_user_id, context_type: "Guild", context_id: guild.id)
      end

      it "does not send another DM" do
        expect(DiscordService).not_to receive(:new)
        handler.send_onboarding_dm_if_needed(context_type: "Guild", context_id: guild.id)
      end
    end

    context "when user is unregistered (onboarding DMs disabled)" do
      it "does not send a DM or create DiscordOnboardingDm rows" do
        expect(DiscordService).not_to receive(:new)
        expect {
          handler.send_onboarding_dm_if_needed(context_type: "Guild", context_id: guild.id)
        }.not_to change(DiscordOnboardingDm, :count)
      end
    end
  end
end
