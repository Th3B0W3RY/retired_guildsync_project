# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPolicy, type: :policy do
  subject { described_class }

  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:guest) { nil }

  describe "#show?" do
    it "allows users to view their own profile" do
      policy = described_class.new(user, user)
      expect(policy.show?).to be true
    end

    it "denies guests from viewing profiles" do
      policy = described_class.new(guest, user)
      expect(policy.show?).to be false
    end

    it "denies users from viewing other users' profiles" do
      policy = described_class.new(user, other_user)
      expect(policy.show?).to be false
    end
  end

  describe "#update?" do
    it "allows users to update their own profile" do
      policy = described_class.new(user, user)
      expect(policy.update?).to be true
    end

    it "denies users from updating other users' profiles" do
      policy = described_class.new(user, other_user)
      expect(policy.update?).to be false
    end

    it "denies guests from updating any profile" do
      policy = described_class.new(guest, user)
      expect(policy.update?).to be false
    end
  end

  describe "#guilds?" do
    it "allows users to view their own guilds" do
      policy = described_class.new(user, user)
      expect(policy.guilds?).to be true
    end

    it "denies users from viewing other users' guilds" do
      policy = described_class.new(user, other_user)
      expect(policy.guilds?).to be false
    end

    it "denies guests from viewing any user's guilds" do
      policy = described_class.new(guest, user)
      expect(policy.guilds?).to be false
    end
  end

  describe "#archive?" do
    it "matches update? (self only)" do
      expect(described_class.new(user, user).archive?).to be true
      expect(described_class.new(user, other_user).archive?).to be false
      expect(described_class.new(guest, user).archive?).to be false
    end
  end

  describe "Scope" do
    let(:scope) { User.all }

    context "for authenticated users" do
      it "returns only the current user" do
        create_list(:user, 3)
        policy_scope = described_class::Scope.new(user, scope).resolve
        expect(policy_scope.count).to eq(1)
        expect(policy_scope.first).to eq(user)
      end
    end

    context "for guests" do
      it "returns no users" do
        create_list(:user, 3)
        policy_scope = described_class::Scope.new(guest, scope).resolve
        expect(policy_scope.count).to eq(0)
      end
    end
  end
end
