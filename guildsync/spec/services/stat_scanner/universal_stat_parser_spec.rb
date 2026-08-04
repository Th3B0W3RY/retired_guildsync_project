# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatScanner::UniversalStatParser do
  describe ".parse" do
    it "extracts colon-separated pairs" do
      text = "Focus: 1695 (4.9%)\nMove Speed: 6.9 m/s"
      expect(described_class.parse(text)).to eq(
        "Focus" => "1695 (4.9%)",
        "Move Speed" => "6.9 m/s"
      )
    end

    it "deduplicates near-duplicate labels" do
      text = "Strength: 10\nstrength: 20"
      out = described_class.parse(text)
      expect(out["Strength"]).to eq("10")
      expect(out["strength (2)"]).to eq("20")
    end

    it "splits on tabs" do
      text = "Level\t99"
      expect(described_class.parse(text)).to eq("Level" => "99")
    end

    it "splits on em dash" do
      text = "Health – 100%"
      expect(described_class.parse(text)).to eq("Health" => "100%")
    end

    it "returns empty hash for blank input" do
      expect(described_class.parse(nil)).to eq({})
      expect(described_class.parse("")).to eq({})
    end

    it "skips lines without a delimiter" do
      expect(described_class.parse("garbage line")).to eq({})
    end

    it "keeps values with colons in the value part" do
      text = "Time: 12:30:45"
      expect(described_class.parse(text)).to eq("Time" => "12:30:45")
    end

    it "splits label + value on a single space when the value is numeric (MMO stat rows)" do
      text = <<~TEXT.strip
        Melee Attack 2680.14
        Ranged Attack 1079.88
        Cast Time 80.3%
        Move Speed 6.9 m/s
      TEXT
      out = described_class.parse(text)
      expect(out["Melee Attack"]).to eq("2680.14")
      expect(out["Ranged Attack"]).to eq("1079.88")
      expect(out["Cast Time"]).to eq("80.3%")
      expect(out["Move Speed"]).to eq("6.9 m/s")
    end

    it "captures defense values with a parenthetical percent" do
      text = "Physical Defense 16437 (67.54%)\nMagic Defense 16331 (67.40%)"
      out = described_class.parse(text)
      expect(out["Physical Defense"]).to eq("16437 (67.54%)")
      expect(out["Magic Defense"]).to eq("16331 (67.40%)")
    end

    it "captures slash stats like crime points" do
      expect(described_class.parse("Crime Points 0/50")).to eq("Crime Points" => "0/50")
    end

    it "drops minimap coordinate lines instead of treating them as stat names" do
      text = <<~TEXT.strip
        W4°35' 31" S19°2'
        Melee Attack 2680.14
      TEXT
      out = described_class.parse(text)
      expect(out.keys).not_to include(match(/W4/))
      expect(out["Melee Attack"]).to eq("2680.14")
    end

    it "drops a coordinate-heavy label even when paired with a stray number" do
      line = %(W4'35' 31" S19 2          53")
      expect(described_class.parse(line)).to eq({})
    end

    it "pairs a label line with the next line when the next line is only a stat value (column OCR)" do
      text = <<~TEXT.strip
        Melee Attack
        2680.14
        Physical Defense
        16437 (67.54%)
      TEXT
      out = described_class.parse(text)
      expect(out["Melee Attack"]).to eq("2680.14")
      expect(out["Physical Defense"]).to eq("16437 (67.54%)")
    end

    it "extracts multiple label/value pairs from one line when OCR merges rows" do
      text = "Melee Attack 2680.14 Ranged Attack 1079.88 Magic Attack 59.50"
      out = described_class.parse(text)
      expect(out["Melee Attack"]).to eq("2680.14")
      expect(out["Ranged Attack"]).to eq("1079.88")
      expect(out["Magic Attack"]).to eq("59.50")
    end

    it "parses move speed with a parenthetical percent" do
      expect(described_class.parse("Move Speed 6.9 m/s (127.1%)")).to eq(
        "Move Speed" => "6.9 m/s (127.1%)"
      )
    end

    it "parses labor-style values with plus inside parentheses" do
      expect(described_class.parse("Labor 5790 (1150 + 4640)")).to eq(
        "Labor" => "5790 (1150 + 4640)"
      )
    end

    it "drops single-digit-only values (common OCR noise)" do
      expect(described_class.parse("Shut 4\nShift 5")).to eq({})
    end

    it "drops action-bar keybind labels like (W)Dn" do
      text = <<~TEXT.strip
        (W)Dn 744
        Focus 1695 (4.9%)
      TEXT
      out = described_class.parse(text)
      expect(out).not_to have_key(match(/Dn|\(W\)/))
      expect(out["Focus"]).to eq("1695 (4.9%)")
    end

    it "drops parenthetical-only labels from hotkey OCR e.g. (Chans)" do
      text = "(Chans) 40\nStamina 178"
      out = described_class.parse(text)
      expect(out.keys).not_to include(match(/Chans/i))
      expect(out["Stamina"]).to eq("178")
    end

    it "drops colon line when label is keybind parenthetical" do
      expect(described_class.parse("(Chans): 40\nStrength: 1452")).to eq("Strength" => "1452")
    end

    it "keeps real stats whose values contain parentheses with digits" do
      expect(described_class.parse("Focus: 1695 (4.9%)")).to eq("Focus" => "1695 (4.9%)")
    end

    it "drops F-key and Shift+N labels" do
      text = "F5 100\nShift 2 50\nAgility 68"
      out = described_class.parse(text)
      expect(out).to eq("Agility" => "68")
    end

    it "drops single-letter and modifier system-key labels" do
      text = <<~TEXT.strip
        W 999
        Tab 1
        Ctrl+Q 0
        Stamina 178
      TEXT
      out = described_class.parse(text)
      expect(out).to eq("Stamina" => "178")
    end

    it "drops mouse and numpad style bar labels" do
      text = "MB2 50\nNumpad 3 10\nStrength 1452"
      out = described_class.parse(text)
      expect(out).to eq("Strength" => "1452")
    end

    it "drops Q + E style chords and Key N OCR" do
      text = "Q + E 12\nKey 7 99\nHonor Points 16845"
      out = described_class.parse(text)
      expect(out).to eq("Honor Points" => "16845")
    end

    it "drops short lowercase OCR fragments paired with bare long integers" do
      text = "rever 7361\nAgility 88"
      out = described_class.parse(text)
      expect(out).not_to have_key("rever")
      expect(out["Agility"]).to eq("88")
    end

    it "keeps allowlisted short labels with plain integer values" do
      expect(described_class.parse("guild 11322")).to eq("guild" => "11322")
    end

    it "drops OCR prose mis-paired as the value for Melee Skill Damage (no digits / stat shape)" do
      text = <<~TEXT.strip
        Melee Skill Damage: Joeven Stars,
        Defense Penetration: 11035
      TEXT
      out = described_class.parse(text)
      expect(out).not_to have_key("Melee Skill Damage")
      expect(out["Defense Penetration"]).to eq("11035")
    end

    it "drops wide-space OCR when the combat stat value is only garbage words" do
      text = "Melee Skill Damage          Joeven Stars"
      expect(described_class.parse(text)).to eq({})
    end

    it "keeps Melee Skill Damage when the value is a percentage" do
      expect(described_class.parse("Melee Skill Damage 140.9%")).to eq("Melee Skill Damage" => "140.9%")
    end

    it "keeps Magic Defense Penetration with a plain integer" do
      expect(described_class.parse("Magic Defense Penetration 200")).to eq("Magic Defense Penetration" => "200")
    end

    it "keeps Faction-style labels when values are words only" do
      text = "Faction: Haranya Alliance\nClass: Blade Dancer"
      expect(described_class.parse(text)).to eq(
        "Faction" => "Haranya Alliance",
        "Class" => "Blade Dancer"
      )
    end

    it "parses a left-panel character sheet (ArcheAge-style) the same as any other layout" do
      text = <<~TEXT.strip
        Faction: Karanya Alliance
        Title: Special Forces Supreme Commander
        Honor Points: 445805
        Melee Attack: 2810.64
        Move Speed: 6.6 m/s (122.0%)
      TEXT
      expect(described_class.parse(text)).to eq(
        "Faction" => "Karanya Alliance",
        "Title" => "Special Forces Supreme Commander",
        "Honor Points" => "445805",
        "Melee Attack" => "2810.64",
        "Move Speed" => "6.6 m/s (122.0%)"
      )
    end

    it "drops system-broadcast sentences split on a colon (long label)" do
      text = <<~TEXT.strip
        The Aegis Island region has fallen into a state of Danger Zone: Stage 5!
        Honor Points: 445805
      TEXT
      out = described_class.parse(text)
      expect(out.keys).not_to include(match(/Aegis|Danger Zone/))
      expect(out["Honor Points"]).to eq("445805")
    end

    it "drops non-bracketed chat where the value is a word-only sentence" do
      text = <<~TEXT.strip
        Grimmjow: lets meet at the gate now everyone hurry
        Stamina: 1924
      TEXT
      out = described_class.parse(text)
      expect(out).not_to have_key("Grimmjow")
      expect(out["Stamina"]).to eq("1924")
    end
  end
end
