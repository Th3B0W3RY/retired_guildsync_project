# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordApplicationCommandService, type: :service do
  include_context "Discord API stubs"

  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:ds) { create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_app") }
  let!(:owner_conn) { create(:user_discord_connection, user: owner, discord_user_id: "d_own_a") }
  let(:officer) { create(:user) }
  let!(:off_conn)   { create(:user_discord_connection, user: officer, discord_user_id: "d_off_a") }
  let!(:off_member) { guild.guild_members.create!(user: officer, role: :moderator, status: :active) }
  let(:regular) { create(:user) }
  let!(:reg_conn)   { create(:user_discord_connection, user: regular, discord_user_id: "d_reg_a") }
  let!(:reg_member) { guild.guild_members.create!(user: regular, role: :member, status: :active) }
  let(:applicant) { create(:user) }

  def interaction(invoker_id, subcommand:, options: [])
    {
      "guild_id" => "svr_app",
      "token"    => "tok_app",
      "member"   => { "user" => { "id" => invoker_id } },
      "data"     => {
        "name"    => "application",
        "options" => [{ "type" => 1, "name" => subcommand.to_s, "options" => options }]
      }
    }
  end

  describe "/application list" do
    it "returns officer_required for a regular member" do
      result = described_class.handle(interaction("d_reg_a", subcommand: :list))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end

    it "returns none_pending when there are no applications" do
      result = described_class.handle(interaction("d_off_a", subcommand: :list))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.application.none_pending"))
    end

    it "lists pending applications" do
      app = create(:guild_application, guild: guild, user: applicant, status: :pending)
      result = described_class.handle(interaction("d_off_a", subcommand: :list))
      expect(result.dig(:data, :embeds, 0, :description)).to include(app.id.to_s)
    end
  end

  describe "/application view" do
    it "returns not_found for an invalid ID" do
      result = described_class.handle(interaction("d_off_a", subcommand: :view,
                                                  options: [{ "name" => "application_id", "value" => 9_999_999 }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.application.not_found"))
    end

    it "returns embed for a valid application" do
      app = create(:guild_application, guild: guild, user: applicant, status: :pending)
      result = described_class.handle(interaction("d_off_a", subcommand: :view,
                                                  options: [{ "name" => "application_id", "value" => app.id }]))
      expect(result.dig(:data, :embeds, 0, :title)).to include(app.id.to_s)
    end
  end

  describe "/application reject" do
    it "rejects a pending application" do
      app = create(:guild_application, guild: guild, user: applicant, status: :pending)
      result = described_class.handle(interaction("d_off_a", subcommand: :reject,
                                                  options: [{ "name" => "application_id", "value" => app.id }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.application.rejected",
                                                             username: applicant.display_name.presence || applicant.username))
      expect(app.reload.status).to eq("rejected")
    end

    it "returns already_processed if already decided" do
      app = create(:guild_application, guild: guild, user: applicant, status: :accepted)
      result = described_class.handle(interaction("d_off_a", subcommand: :reject,
                                                  options: [{ "name" => "application_id", "value" => app.id }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.application.already_processed"))
    end
  end

  describe "/application accept" do
    it "returns deferred for a pending application" do
      app = create(:guild_application, guild: guild, user: applicant, status: :pending)
      result = described_class.handle(interaction("d_off_a", subcommand: :accept,
                                                  options: [{ "name" => "application_id", "value" => app.id }]))
      expect(result[:type]).to eq(5)
    end
  end

  # =========================================================================
  # process_accept (called by DiscordCommandJob)
  # =========================================================================
  describe "#process_accept" do
    let(:service) { described_class.new }
    let!(:application) { create(:guild_application, guild: guild, user: applicant, status: :pending) }

    before do
      service.instance_variable_set(:@guild, guild)
      service.instance_variable_set(:@user, officer)
      service.instance_variable_set(:@interaction_token, "tok_accept")
      service.instance_variable_set(:@guild_member, off_member)

      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
    end

    it "accepts the application and creates a guild member" do
      service.send(:process_accept, { application_id: application.id }.with_indifferent_access)

      expect(application.reload.status).to eq("accepted")
      expect(guild.guild_members.exists?(user: applicant)).to be true
    end

    it "is idempotent when application is already accepted" do
      application.update!(status: :accepted)
      guild.guild_members.create!(user: applicant, role: :member, status: :active)

      expect {
        service.send(:process_accept, { application_id: application.id }.with_indifferent_access)
      }.not_to change(GuildMember, :count)
    end
  end
end
