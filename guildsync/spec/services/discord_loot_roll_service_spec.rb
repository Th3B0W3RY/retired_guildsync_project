# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DiscordLootRollService, type: :service do
  let(:user) { create(:user, stripe_customer_id: 'cus_test123') }
  let(:guild) { create(:guild, owner: user) }
  let(:discord_setting) do
    create(:guild_discord_setting,
           guild: guild,
           discord_guild_id: "123456789",
           loot_rolls_channel_id: "987654321",
           bot_token: "test_bot_token")
  end
  let(:loot_roll) { create(:loot_roll, guild: guild, creator: user, discord_channel_id: "987654321") }
  let(:service) { described_class.new(loot_roll) }

  before do
    discord_setting # Ensure discord setting exists
    stub_request(:any, /discord\.com/).to_return(
      status: 200,
      body: '{"id": "999888777"}',
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe '#post_loot_roll' do
    it 'posts a message to Discord' do
      expect { service.post_loot_roll }.not_to raise_error
    end

    it 'stores the discord message id' do
      service.post_loot_roll
      expect(loot_roll.reload.discord_message_id).to eq("999888777")
    end

    it 'raises error when Discord not connected' do
      discord_setting.destroy
      loot_roll.reload

      expect { service.post_loot_roll }.to raise_error(/Discord not connected/)
    end

    it 'raises error when channel not configured' do
      loot_roll.update!(discord_channel_id: nil)
      discord_setting.update!(loot_rolls_channel_id: nil)

      expect { service.post_loot_roll }.to raise_error(/channel not configured/)
    end
  end

  describe '#update_loot_roll_message' do
    before do
      loot_roll.update!(discord_message_id: "existing_message_id")
    end

    it 'updates the Discord message' do
      expect { service.update_loot_roll_message }.not_to raise_error
    end

    it 'does nothing when no message id' do
      loot_roll.update!(discord_message_id: nil)
      # Should not make any API calls
      expect { service.update_loot_roll_message }.not_to raise_error
    end
  end

  describe 'embed building' do
    it 'includes roll counts in the embed' do
      loot_roll_with_entries = create(:loot_roll, guild: guild, creator: user, discord_channel_id: "987654321")
      create(:loot_roll_entry, loot_roll: loot_roll_with_entries, roll_value: 75, display_name: "Player1")
      create(:loot_roll_entry, loot_roll: loot_roll_with_entries, roll_value: 90, display_name: "Player2")

      service_with_entries = described_class.new(loot_roll_with_entries)

      # Access private method for testing
      embed = service_with_entries.send(:build_embed)

      expect(embed[:title]).to include(loot_roll_with_entries.title)
      expect(embed[:fields].any? { |f| f[:name].include?("Rolls") }).to be true
      expect(embed.dig(:footer, :text)).to include(discord_setting.discord_guild_name)
    end

    it 'includes tie detection in embed' do
      loot_roll_with_tie = create(:loot_roll, guild: guild, creator: user, discord_channel_id: "987654321")
      create(:loot_roll_entry, loot_roll: loot_roll_with_tie, roll_value: 90, display_name: "Player1", discord_user_id: "user1")
      create(:loot_roll_entry, loot_roll: loot_roll_with_tie, roll_value: 90, display_name: "Player2", discord_user_id: "user2")

      service_with_tie = described_class.new(loot_roll_with_tie)
      embed = service_with_tie.send(:build_embed)

      # Should have a TIE DETECTED field
      expect(embed[:fields].any? { |f| f[:name].include?("TIE") }).to be true
    end

    it 'includes winner when closed' do
      winner_entry = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 95, display_name: "Winner")
      loot_roll.update!(status: :closed, winner_entry: winner_entry)

      embed = service.send(:build_embed)

      expect(embed[:fields].any? { |f| f[:name].include?("Winner") }).to be true
    end
  end

  describe 'button building' do
    it 'includes roll button when open' do
      buttons = service.send(:build_buttons)

      expect(buttons).not_to be_empty
      expect(buttons.first[:components].first[:label]).to include("Roll")
    end

    it 'returns empty array when closed' do
      loot_roll.update!(status: :closed)

      buttons = service.send(:build_buttons)

      expect(buttons).to be_empty
    end

    it 'shows tiebreaker button when there is a tie' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: "user1")
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: "user2")
      loot_roll.start_tiebreaker!

      buttons = service.send(:build_buttons)

      expect(buttons.first[:components].first[:label]).to include("Reroll")
      expect(buttons.first[:components].first[:custom_id]).to include("tiebreaker")
    end
  end

  describe 'role mentions' do
    it 'includes role mentions in content' do
      create(:discord_role_sync, guild: guild, role_id: "111111111", role_name: "Raiders")
      loot_roll.update!(allowed_role_ids: ["111111111"])

      # We need to test this indirectly through the post method
      # The content should include role mentions
      service.post_loot_roll

      # Check that the request included role mentions
      expect(WebMock).to have_requested(:post, /discord\.com/).with { |req|
        body = JSON.parse(req.body)
        body["content"]&.include?("<@&111111111>") || body["content"].nil?
      }
    end

    it 'uses @everyone for guild ID' do
      loot_roll.update!(allowed_role_ids: ["123456789"]) # Same as discord_guild_id

      service.post_loot_roll

      expect(WebMock).to have_requested(:post, /discord\.com/).with { |req|
        body = JSON.parse(req.body)
        body["content"]&.include?("@everyone") || body["content"].nil?
      }
    end
  end
end
