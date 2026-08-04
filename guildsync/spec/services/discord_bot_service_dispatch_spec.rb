# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordBotService, type: :service do
  let(:service) { described_class.new }
  let(:bot) { instance_double(Discordrb::Bot) }
  let(:user) { instance_double(Discordrb::User, id: 123, username: "testuser") }
  let(:interaction) { instance_double(Discordrb::Interaction, token: "test_token", data: { "resolved" => {} }) }
  let(:event) do
    instance_double(
      Discordrb::Events::ApplicationCommandEvent,
      bot: bot,
      user: user,
      server_id: 456,
      command_name: :event,
      subcommand: :list,
      options: { "some" => "option" },
      interaction: interaction
    )
  end

  before do
    allow(Discordrb::Bot).to receive(:new).and_return(bot)
    allow(bot).to receive(:ready)
    allow(bot).to receive(:button)
    allow(bot).to receive(:reaction_add)
    allow(bot).to receive(:reaction_remove)
    allow(bot).to receive(:message)
    allow(bot).to receive(:application_command).and_return(double(subcommand: nil))
    allow(bot).to receive_message_chain(:profile, :username).and_return("GuildSync")
    allow(bot).to receive_message_chain(:profile, :id).and_return(1441181242845560833)
  end

  describe "#build_gateway_interaction" do
    it "converts event data to the format services expect" do
      result = service.send(:build_gateway_interaction, event)

      expect(result["guild_id"]).to eq("456")
      expect(result["token"]).to eq("test_token")
      expect(result["member"]["user"]["id"]).to eq("123")
      expect(result["data"]["name"]).to eq("event")
      expect(result["data"]["options"][0]["name"]).to eq("list")
      expect(result["data"]["options"][0]["options"][0]["name"]).to eq("some")
    end

    it "handles top-level commands without subcommands" do
      allow(event).to receive(:subcommand).and_return(nil)
      allow(event).to receive(:command_name).and_return(:invite)

      result = service.send(:build_gateway_interaction, event)
      expect(result["data"]["name"]).to eq("invite")
      expect(result["data"]["options"][0]["name"]).to eq("some")
    end
  end

  describe "#respond_to_gateway_interaction" do
    it "calls event.respond for type 4 responses" do
      result = { type: 4, data: { content: "Hello", flags: 64 } }
      expect(event).to receive(:respond).with(content: "Hello", ephemeral: true)
      service.send(:respond_to_gateway_interaction, event, result)
    end

    it "calls event.defer for type 5 responses" do
      result = { type: 5, data: { flags: 64 } }
      expect(event).to receive(:defer).with(ephemeral: true)
      service.send(:respond_to_gateway_interaction, event, result)
    end

    it "handles embeds and components" do
      embeds = [{ title: "T" }]
      components = [{ type: 1 }]
      result = { type: 4, data: { embeds: embeds, components: components } }
      expect(event).to receive(:respond).with(embeds: embeds, components: components, ephemeral: false)
      service.send(:respond_to_gateway_interaction, event, result)
    end
  end

  describe "#dispatch_application_command" do
    it "routes to the correct service and responds" do
      expect(DiscordEventCommandService).to receive(:handle).and_return({ type: 4, data: { content: "Done" } })
      expect(event).to receive(:respond).with(content: "Done", ephemeral: false)

      service.send(:dispatch_application_command, event)
    end

    it "responds with error if service fails" do
      allow(DiscordEventCommandService).to receive(:handle).and_raise(StandardError.new("Boom"))
      expect(event).to receive(:respond).with(content: /error occurred/, ephemeral: true)

      service.send(:dispatch_application_command, event)
    end
  end
end
