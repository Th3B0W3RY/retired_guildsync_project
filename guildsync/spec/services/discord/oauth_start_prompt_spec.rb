# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discord::OAuthStartPrompt do
  def prompt_for(**overrides)
    defaults = {
      silent_reauth: false,
      oauth_from: "login",
      link_only: false,
      seen_before: false,
      has_discord_uid: false,
      cookie_silent_attempted: false
    }
    described_class.new(**defaults.merge(overrides)).call
  end

  describe "#call" do
    it "returns 'none' for an app-triggered silent re-auth" do
      expect(prompt_for(silent_reauth: true)).to eq("none")
    end

    it "returns nil when linking Discord to a signed-in account" do
      expect(prompt_for(link_only: true, seen_before: true, has_discord_uid: true)).to be_nil
    end

    it "returns 'none' for a returning login with discord_seen_before" do
      expect(prompt_for(oauth_from: "login", seen_before: true)).to eq("none")
    end

    it "returns 'none' for a login when a discord_uid cookie is present" do
      expect(prompt_for(oauth_from: "login", has_discord_uid: true)).to eq("none")
    end

    it "returns 'none' for a login when the cookie silent path was attempted but failed" do
      expect(prompt_for(oauth_from: "login", cookie_silent_attempted: true)).to eq("none")
    end

    it "returns nil for a brand-new login with no prior evidence" do
      expect(prompt_for(oauth_from: "login")).to be_nil
    end

    it "returns nil for a first-time signup with no prior Discord use" do
      expect(prompt_for(oauth_from: "signup")).to be_nil
    end

    it "returns 'none' for a signup when the user has authorized before" do
      expect(prompt_for(oauth_from: "signup", seen_before: true)).to eq("none")
    end

    it "prioritizes silent_reauth even when link_only is also set" do
      expect(prompt_for(silent_reauth: true, link_only: true)).to eq("none")
    end
  end
end
