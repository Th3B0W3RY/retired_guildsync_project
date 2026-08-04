# frozen_string_literal: true

require "rails_helper"

RSpec.describe GearStatScanActivityLog do
  let(:guild) { create(:guild) }
  let(:actor) { create(:user) }

  before do
    guild.guild_members.create!(user: actor, role: :member, status: :active)
  end

  describe ".log_successful_upload" do
    it "no-ops when guild is nil" do
      expect {
        described_class.log_successful_upload(guild: nil, initiated_by: actor, game_name: "WoW")
      }.not_to change(GuildActivityLog, :count)
    end

    it "no-ops when initiated_by is nil" do
      expect {
        described_class.log_successful_upload(guild: guild, initiated_by: nil, game_name: "WoW")
      }.not_to change(GuildActivityLog, :count)
    end

    context "when billing subject is the actor" do
      before { allow(Ocr::BillingSubject).to receive(:for_gear_upload).and_return(actor) }

      it "logs gear_uploaded with standard copy and no ocr_billed_to_name" do
        expect {
          described_class.log_successful_upload(guild: guild, initiated_by: actor, game_name: "WoW")
        }.to change(GuildActivityLog, :count).by(1)

        log = GuildActivityLog.last
        expect(log.guild_id).to eq(guild.id)
        expect(log.user_id).to eq(actor.id)
        expect(log.action_type).to eq("gear_uploaded")
        expect(log.description).to eq(I18n.t("gear.activity.uploaded", game: "WoW"))
        expect(log.metadata).not_to have_key("ocr_billed_to_name")
      end
    end

    context "when billing subject is the guild owner" do
      let(:leader) { guild.owner }

      before { allow(Ocr::BillingSubject).to receive(:for_gear_upload).and_return(leader) }

      it "logs shared-plan copy and ocr_billed_to_name in metadata" do
        described_class.log_successful_upload(guild: guild, initiated_by: actor, game_name: "WoW")

        log = GuildActivityLog.last
        expect(log.description).to eq(
          I18n.t("gear.activity.uploaded_shared_guild_plan", game: "WoW", leader_name: leader.display_name)
        )
        expect(log.metadata["ocr_billed_to_name"]).to eq(leader.display_name)
      end
    end
  end
end
