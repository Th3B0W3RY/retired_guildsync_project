# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfanityListUpdateJob, type: :job do
  let(:plain_body) { "word1\nword2\n# comment\nword3\n" }
  let(:json_body) { '{"words":["a","b","c"]}' }

  before do
    stub_const("PROFANITY_SOURCES", [
      { name: "TestPlain", url: "https://example.com/plain.txt", format: :plain, enabled: true },
      { name: "TestJSON", url: "https://example.com/words.json", format: :json, json_path: "words", enabled: true }
    ])
  end

  describe "#perform" do
    it "fetches from URL sources and merges words" do
      stub_request(:get, "https://example.com/plain.txt").to_return(body: plain_body)
      stub_request(:get, "https://example.com/words.json").to_return(body: json_body)

      expect { described_class.new.perform }.to change(BlockedWord, :count)
      expect(BlockedWord.pluck(:word)).to include("word1", "word2", "word3", "a", "b", "c")
    end

    it "handles source failures gracefully and continues" do
      stub_request(:get, "https://example.com/plain.txt").to_return(body: "ok\n")
      stub_request(:get, "https://example.com/words.json").to_return(status: 500)

      result = described_class.new.perform
      expect(result[:errors]).to be_an(Array)
      expect(result[:sources_checked].map { |s| s["status"] }).to include("success", "failed")
      expect(BlockedWord.count).to be >= 1
    end

    it "only adds new words (idempotent for existing)" do
      create(:blocked_word, word: "existing")
      stub_request(:get, "https://example.com/plain.txt").to_return(body: "existing\nnewword\n")
      stub_request(:get, "https://example.com/words.json").to_return(body: '{"words":[]}')

      expect { described_class.new.perform }.to change(BlockedWord, :count).by(1)
      expect(BlockedWord.pluck(:word)).to include("existing", "newword")
    end

    it "creates a ProfanityUpdateLog" do
      stub_request(:get, "https://example.com/plain.txt").to_return(body: "x\n")
      stub_request(:get, "https://example.com/words.json").to_return(body: '{"words":[]}')

      expect { described_class.new.perform }.to change(ProfanityUpdateLog, :count).by(1)
      log = ProfanityUpdateLog.last
      expect(log.total_words).to be >= 0
      expect(log.sources_checked).to be_an(Array)
    end

    it "resets BlockedContentFilter and cache" do
      stub_request(:get, "https://example.com/plain.txt").to_return(body: "x\n")
      stub_request(:get, "https://example.com/words.json").to_return(body: '{"words":[]}')
      allow(BlockedContentFilter).to receive(:reset!)
      allow(Rails.cache).to receive(:delete)

      described_class.new.perform

      expect(BlockedContentFilter).to have_received(:reset!)
      expect(Rails.cache).to have_received(:delete).with(BlockedContentFilter::CACHE_KEY)
    end
  end
end
