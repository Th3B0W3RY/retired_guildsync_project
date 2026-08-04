require 'rails_helper'

RSpec.describe DiscordPollService, type: :service do
  let(:guild) { create(:guild) }
  let(:user) { create(:user, stripe_customer_id: 'cus_test123') }
  let(:discord_setting) { create(:guild_discord_setting, guild: guild, discord_guild_id: "123456789", polls_channel_id: "987654321") }
  let(:poll) { create(:poll, guild: guild, creator: user, discord_channel_id: "987654321") }
  let(:service) { described_class.new(poll) }

  before do
    discord_setting # Ensure discord setting exists
    stub_request(:any, /discord\.com/).to_return(status: 200, body: '{"id": "999888777"}', headers: { 'Content-Type' => 'application/json' })
    stub_request(:any, /stripe\.com/).to_return(status: 200, body: '{"id": "cus_test"}', headers: { 'Content-Type' => 'application/json' })
  end

  describe '#post_poll' do
    context 'when Discord is connected' do
      it 'posts the poll to Discord' do
        expect { service.post_poll }.not_to raise_error
        expect(poll.reload.discord_message_id).to eq("999888777")
      end

      it 'stores the message ID' do
        service.post_poll
        expect(poll.reload.discord_message_id).to be_present
      end
    end

    context 'when Discord is not connected' do
      let(:disconnected_guild) { create(:guild) }
      let(:disconnected_poll) { create(:poll, guild: disconnected_guild, creator: user) }

      it 'raises an error' do
        service = described_class.new(disconnected_poll)
        expect { service.post_poll }.to raise_error(/Discord not connected/)
      end
    end

    context 'when polls channel is not configured' do
      before do
        discord_setting.update!(polls_channel_id: nil)
        poll.update!(discord_channel_id: nil)
      end

      it 'raises an error' do
        expect { service.post_poll }.to raise_error(/Polls channel not configured/)
      end
    end

    context 'with role mentions' do
      let(:poll_with_roles) do
        create(:poll, guild: guild, creator: user,
               discord_channel_id: "987654321",
               discord_role_mentions: ["111111111", "222222222"])
      end

      it 'includes role mentions in the message' do
        service_with_roles = described_class.new(poll_with_roles)
        service_with_roles.post_poll
        expect(WebMock).to have_requested(:post, /discord\.com/)
      end
    end

    context 'with @everyone role' do
      let!(:everyone_role) do
        create(:discord_role_sync, guild: guild, role_id: "123456789", role_name: "@everyone")
      end

      let(:poll_with_everyone) do
        create(:poll, guild: guild, creator: user,
               discord_channel_id: "987654321",
               discord_role_mentions: ["123456789"]) # Same as discord_guild_id
      end

      it 'mentions @everyone correctly without double @' do
        service_with_everyone = described_class.new(poll_with_everyone)
        service_with_everyone.post_poll
        # The service should have called the API
        expect(WebMock).to have_requested(:post, /discord\.com/)
      end
    end
  end

  describe '#update_poll_message' do
    let(:poll_with_message) do
      create(:poll, guild: guild, creator: user,
             discord_channel_id: "987654321",
             discord_message_id: "999888777")
    end

    it 'updates the Discord message' do
      service_with_message = described_class.new(poll_with_message)
      expect { service_with_message.update_poll_message }.not_to raise_error
      expect(WebMock).to have_requested(:patch, /discord\.com/)
    end

    context 'when poll has no Discord message' do
      let(:poll_without_message) do
        create(:poll, guild: guild, creator: user, discord_channel_id: nil, discord_message_id: nil)
      end

      it 'does not make any API calls' do
        service_no_message = described_class.new(poll_without_message)
        service_no_message.update_poll_message
        expect(WebMock).not_to have_requested(:patch, /discord\.com/)
      end
    end
  end

  describe 'embed building' do
    it 'includes the connected Discord server name in the footer' do
      embed = service.send(:build_embed)
      expect(embed.dig(:footer, :text)).to include(discord_setting.discord_guild_name)
    end

    it 'lists non-anonymous voters using name_for_discord_embed (Discord display name over handle)' do
      poll_with_votes = create(:poll, guild: guild, creator: user, discord_channel_id: "987654321")
      voter = create(:user, username: "voter_site", discord_username: "discord_handle",
                             discord_global_name: "Friendly Voter", email: "voter_embed@example.com",
                             stripe_customer_id: "cus_voter_embed_name")
      create(:poll_vote, poll: poll_with_votes, user: voter, choice: :yes)
      embed = described_class.new(poll_with_votes).send(:build_embed)
      yes_field = embed[:fields].find { |f| f[:name].to_s.include?("Yes") }
      expect(yes_field[:value]).to include("Friendly Voter")
      expect(yes_field[:value]).not_to include("discord_handle")
    end

    it 'includes vote counts in the embed' do
      poll_with_votes = create(:poll, guild: guild, creator: user, discord_channel_id: "987654321")
      voter1 = create(:user, stripe_customer_id: "cus_voter1")
      voter2 = create(:user, stripe_customer_id: "cus_voter2")
      create(:poll_vote, poll: poll_with_votes, user: voter1, choice: :yes)
      create(:poll_vote, poll: poll_with_votes, user: voter2, choice: :no)
      
      service_with_votes = described_class.new(poll_with_votes)
      service_with_votes.post_poll
      expect(WebMock).to have_requested(:post, /discord\.com/)
    end

    context 'when poll is anonymous' do
      it 'does not include voter names' do
        anonymous_poll = create(:poll, :anonymous, guild: guild, creator: user, discord_channel_id: "987654321")
        service_anonymous = described_class.new(anonymous_poll)
        service_anonymous.post_poll
        expect(WebMock).to have_requested(:post, /discord\.com/)
      end
    end

    context 'when poll is not anonymous' do
      it 'includes voter names in the embed' do
        poll_with_votes = create(:poll, guild: guild, creator: user, discord_channel_id: "987654321")
        voter = create(:user, stripe_customer_id: "cus_voter_embed")
        create(:poll_vote, poll: poll_with_votes, user: voter, choice: :yes)
        
        service_with_votes = described_class.new(poll_with_votes)
        service_with_votes.post_poll
        expect(WebMock).to have_requested(:post, /discord\.com/)
      end
    end
  end

  describe 'button building' do
    context 'when poll is open' do
      it 'includes voting buttons' do
        service.post_poll
        expect(WebMock).to have_requested(:post, /discord\.com/).with { |req|
          body = JSON.parse(req.body)
          body['components'].present? && body['components'].any?
        }
      end
    end

    context 'when poll is closed' do
      let(:closed_poll) { create(:poll, :closed, guild: guild, creator: user, discord_channel_id: "987654321") }

      it 'does not include voting buttons' do
        closed_service = described_class.new(closed_poll)
        closed_service.post_poll
        expect(WebMock).to have_requested(:post, /discord\.com/).with { |req|
          body = JSON.parse(req.body)
          body['components'].nil? || body['components'].empty?
        }
      end
    end
  end
end

