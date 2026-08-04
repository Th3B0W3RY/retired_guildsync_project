# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockedWord, type: :model do
  describe "validations" do
    it "validates uniqueness of word" do
      create(:blocked_word, word: "badword")
      duplicate = build(:blocked_word, word: "badword")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:word]).to be_present
    end

    it "requires word" do
      bw = build(:blocked_word, word: "")
      expect(bw).not_to be_valid
      expect(bw.errors[:word]).to be_present
    end

    it "allows category from CATEGORIES" do
      bw = build(:blocked_word, category: "profanity")
      expect(bw).to be_valid
    end
  end

  describe "scopes" do
    it "active returns only active words" do
      active_word = create(:blocked_word, active: true)
      create(:blocked_word, active: false, word: "inactiveword")
      expect(BlockedWord.active).to include(active_word)
      expect(BlockedWord.active.count).to eq(1)
    end
  end

  describe "terms_for_filter" do
    it "returns pluck of active words" do
      create(:blocked_word, word: "foo", active: true)
      create(:blocked_word, word: "bar", active: false)
      expect(BlockedWord.terms_for_filter).to contain_exactly("foo")
    end
  end
end
