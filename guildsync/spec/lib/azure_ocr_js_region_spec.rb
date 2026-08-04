# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# Stat extraction is content-based and game-agnostic: azure_ocr.js keeps text from anywhere on
# screen (no position/geometry filter) and only drops bracketed chat. What counts as a stat is
# decided downstream by StatScanner::UniversalStatParser.
RSpec.describe "azure_ocr.js line extraction" do
  let(:script_path) { Rails.root.join("lib/scripts/azure_ocr.js").to_s }

  def node_eval(code)
    out, err, status = Open3.capture3("node", "-e", code)
    expect(status.success?).to be(true), "node failed: #{err}\n#{out}"
    out
  end

  describe "getLinePosition bounding box derivation" do
    def line_position(line_json)
      code = <<~JS
        const m = require(#{JSON.generate(script_path)});
        console.log(JSON.stringify(m.getLinePosition(#{line_json}, 3)));
      JS
      JSON.parse(node_eval(code))
    end

    it "derives x, xMax, y, and h from a four-point bounding polygon" do
      pos = line_position(<<~JSON)
        { boundingPolygon: [
          { x: 10, y: 5 }, { x: 100, y: 5 }, { x: 100, y: 25 }, { x: 10, y: 25 }
        ] }
      JSON
      expect(pos).to eq("x" => 10, "xMax" => 100, "y" => 5, "h" => 20, "noBbox" => false)
    end

    it "returns a finite xMax for a degenerate single-point polygon" do
      pos = line_position("{ boundingPolygon: [{ x: 42, y: 7 }] }")
      expect(pos["xMax"]).to eq(42)
      expect(pos["h"]).to eq(1)
      expect(pos["noBbox"]).to be(false)
    end

    it "falls back to noBbox when the polygon is missing" do
      pos = line_position("{}")
      expect(pos).to eq("x" => 0, "xMax" => 0, "y" => 30, "h" => 0, "noBbox" => true)
    end

    it "falls back to noBbox when the polygon is empty" do
      pos = line_position("{ boundingPolygon: [] }")
      expect(pos["noBbox"]).to be(true)
      expect(pos["xMax"]).to eq(0)
    end

    it "falls back to noBbox when polygon points lack numeric coordinates" do
      pos = line_position('{ boundingPolygon: [{ x: "a", y: null }, { foo: 1 }] }')
      expect(pos["noBbox"]).to be(true)
      expect(pos["xMax"]).to eq(0)
    end
  end

  describe "extractTextLines (content-based, position-independent)" do
    it "keeps stat lines from any horizontal position (left and right panels) in reading order" do
      code = <<~JS
        const m = require(#{JSON.generate(script_path)});
        const body = {
          readResult: {
            blocks: [
              { lines: [
                { text: "Faction: Karanya Alliance", boundingPolygon: [
                  { x: 30, y: 60 }, { x: 230, y: 60 }, { x: 230, y: 80 }, { x: 30, y: 80 }
                ] },
                { text: "Power: 1234", boundingPolygon: [
                  { x: 520, y: 60 }, { x: 640, y: 60 }, { x: 640, y: 80 }, { x: 520, y: 80 }
                ] }
              ] }
            ]
          }
        };
        console.log(JSON.stringify(m.extractTextLines(body)));
      JS
      expect(JSON.parse(node_eval(code))).to eq(["Faction: Karanya Alliance", "Power: 1234"])
    end

    it "drops bracketed chat lines regardless of position" do
      code = <<~JS
        const m = require(#{JSON.generate(script_path)});
        const body = {
          readResult: {
            blocks: [
              { lines: [
                { text: "Honor Points: 445805", boundingPolygon: [
                  { x: 30, y: 200 }, { x: 230, y: 200 }, { x: 230, y: 220 }, { x: 30, y: 220 }
                ] },
                { text: "[Nation] Grimmjow: 100k", boundingPolygon: [
                  { x: 30, y: 900 }, { x: 300, y: 900 }, { x: 300, y: 920 }, { x: 30, y: 920 }
                ] }
              ] }
            ]
          }
        };
        console.log(JSON.stringify(m.extractTextLines(body)));
      JS
      expect(JSON.parse(node_eval(code))).to eq(["Honor Points: 445805"])
    end

    it "uses the plain content fallback when no line objects are present" do
      code = <<~JS
        const m = require(#{JSON.generate(script_path)});
        const body = { readResult: { content: "Power: 1234\\nDefense: 56" } };
        console.log(JSON.stringify(m.extractTextLines(body)));
      JS
      expect(JSON.parse(node_eval(code))).to eq(["Power: 1234", "Defense: 56"])
    end
  end
end
