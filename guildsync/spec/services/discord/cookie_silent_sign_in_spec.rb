# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discord::CookieSilentSignIn do
  let(:user) { create(:user, auth_method: "discord", discord_user_id: "111222333") }

  describe ".call" do
    it "returns :not_applicable when the discord_uid is blank" do
      result = described_class.call(nil)
      expect(result).to be_not_applicable
      expect(result.user).to be_nil
    end

    it "returns :fallthrough when no connection exists for the uid" do
      result = described_class.call("999000999")
      expect(result).to be_fallthrough
      expect(result.user).to be_nil
    end

    it "returns :fallthrough when the connection has no refresh token" do
      create(:user_discord_connection, user: user, discord_user_id: "111222333",
             refresh_token: nil, expires_at: 1.hour.from_now)

      result = described_class.call("111222333")
      expect(result).to be_fallthrough
    end

    it "returns :signed_in with the user when the token is valid (no refresh needed)" do
      create(:user_discord_connection, user: user, discord_user_id: "111222333",
             refresh_token: "ref", expires_at: 1.hour.from_now)

      result = described_class.call("111222333")
      expect(result).to be_signed_in
      expect(result.user).to eq(user)
    end

    it "refreshes an expired token and returns :signed_in" do
      create(:user_discord_connection, user: user, discord_user_id: "111222333",
             refresh_token: "ref", expires_at: 1.hour.ago)
      allow_any_instance_of(UserDiscordConnection).to receive(:refresh!).and_return(true)

      result = described_class.call("111222333")
      expect(result).to be_signed_in
      expect(result.user).to eq(user)
    end

    it "returns :fallthrough when refresh raises (revoked/expired token)" do
      create(:user_discord_connection, user: user, discord_user_id: "111222333",
             refresh_token: "ref", expires_at: 1.hour.ago)
      allow_any_instance_of(UserDiscordConnection).to receive(:refresh!)
        .and_raise(Discord::DiscordTokenRevokedError, "revoked")

      result = described_class.call("111222333")
      expect(result).to be_fallthrough
      expect(result.user).to be_nil
    end
  end
end
