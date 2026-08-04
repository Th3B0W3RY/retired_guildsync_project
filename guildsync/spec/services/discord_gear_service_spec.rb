# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordGearService, type: :service do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let!(:discord_setting) { create(:guild_discord_setting, guild: guild, discord_guild_id: "dg_gear_spec") }
  let!(:owner_conn) { create(:user_discord_connection, user: owner, discord_user_id: "du_gear_spec") }
  let(:game) { guild.games.first }

  let(:minimal_png) do
    [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
      0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
      0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00,
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack("C*")
  end

  let(:interaction) do
    {
      "guild_id" => "dg_gear_spec",
      "member" => { "user" => { "id" => "du_gear_spec" } },
      "data" => {
        "resolved" => {
          "attachments" => {
            "1" => {
              "url" => "https://cdn.discordapp.com/attachments/1/2/image.png",
              "content_type" => "image/png"
            }
          }
        }
      }
    }
  end

  describe ".handle_upload_command" do
    let(:download_tempfile) do
      tmp = Tempfile.new(["discord_gear_dl", ".png"])
      tmp.binmode
      tmp.write(minimal_png)
      tmp.rewind
      tmp
    end

    it "passes Ocr::ChannelRequest into GearOcrService for usage and OcrRequest metadata" do
      allow(DiscordGearService).to receive(:download_image).and_return(download_tempfile)
      expect(GearOcrService).to receive(:process_image).with(
        kind_of(Tempfile),
        game,
        hash_including(
          user: owner,
          request: an_object_having_attributes(
            user_agent: "Discord/gear-upload",
            remote_ip: nil
          )
        )
      ).and_return({
        success: true,
        raw_text: "Gear Score: 1",
        data: { "Gear Score" => 1 }
      })

      allow(GearEmbeddingService).to receive(:generate_embedding).and_return([0.1])
      allow(GearEmbeddingService).to receive(:validate_embedding).and_return({ valid: true, warning: nil })

      result = described_class.handle_upload_command(interaction)
      expect(result.dig(:data, :content)).to include("uploaded successfully")
    end
  end
end
