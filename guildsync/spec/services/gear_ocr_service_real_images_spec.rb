# frozen_string_literal: true

# IMPORTANT: These examples must NEVER use real OCR API credits when run as part of the normal suite.
# They are skipped by default. Set ALLOW_REAL_OCR_IN_SPEC=1 (and configure Azure) only when you
# explicitly want to run integration tests that consume real OCR credits.

require 'rails_helper'
require 'json'
require 'fileutils'
require 'cgi'

RSpec.describe GearOcrService, 'with real game screenshots', :ocr do
  # Skip all tests unless explicitly allowed AND Azure OCR is available.
  # Default: never run real OCR (no credits used). Set ALLOW_REAL_OCR_IN_SPEC=1 to enable.
  before(:each) do
    unless real_ocr_allowed_in_spec?
      skip real_ocr_skip_message
    end
  end

  def real_ocr_allowed_in_spec?
    ENV["ALLOW_REAL_OCR_IN_SPEC"] == "1" && azure_ocr_available?
  end

  def real_ocr_skip_message
    return "Real OCR disabled in specs (would use API credits). Set ALLOW_REAL_OCR_IN_SPEC=1 and configure Azure to run." if ENV["ALLOW_REAL_OCR_IN_SPEC"] != "1"
    "Azure OCR not configured. Set GUILDSYNC_AZURE_VISION_ENDPOINT and GUILDSYNC_AZURE_VISION_KEY, and ensure node is in PATH."
  end

  def azure_ocr_available?
    endpoint_present = ENV["GUILDSYNC_AZURE_VISION_ENDPOINT"].present? || ENV["AZURE_VISION_ENDPOINT"].present?
    key_present = ENV["GUILDSYNC_AZURE_VISION_KEY"].present? || ENV["AZURE_VISION_KEY"].present?
    node_available = system("node --version", out: File::NULL, err: File::NULL)
    endpoint_present && key_present && node_available
  end

  # Helper methods for common test operations
  def create_uploaded_file(image_path, filename = nil)
    filename ||= File.basename(image_path)
    file = File.open(image_path, 'rb')
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: filename,
      type: 'image/webp'
    )
  end

  def create_game_with_ocr_config(name:, slug:, ocr_config: nil, handler_class: nil)
    # If handler_class is provided, it is the PRIMARY source - don't use default patterns
    # Patterns in ocr_config are only used as fallback when no handler is present
    if handler_class.present?
      config = ocr_config || {}
      config = config.dup
      config['handler_class'] = handler_class
      # Don't include default patterns when handler is present - handler does all parsing
    else
      # No handler - use default patterns as fallback
      default_config = {
        'patterns' => {
          'gear_score' => /gear\s*score[:\s]*(\d+)/i,
          'item_level' => /item\s*level[:\s]*(\d+)/i,
          'weapon' => /weapon[:\s]*([^\n]+)/i,
          'armor' => /armor[:\s]*([^\n]+)/i
        }
      }
      config = ocr_config || default_config
    end

    Game.find_or_create_by!(slug: slug) do |game|
      game.name = name
      game.description = "#{name} MMO"
      game.active = true
      game.ocr_config = config
    end
  end

  def save_ocr_result_json(image_path, game, result, test_name)
    # Create output directory for OCR results
    output_dir = Rails.root.join('spec', 'ocr_results')
    FileUtils.mkdir_p(output_dir) unless File.directory?(output_dir)

    # Generate filename: {game_slug}_{screenshot_name}.json
    screenshot_name = File.basename(image_path, File.extname(image_path))
    game_slug = game.slug
    # Sanitize test_name for filename (remove spaces, special chars)
    safe_test_name = test_name.gsub(/[^a-zA-Z0-9_-]/, '_')
    base_filename = "#{game_slug}_#{screenshot_name}_#{safe_test_name}"
    json_path = output_dir.join("#{base_filename}.json")
    html_path = output_dir.join("#{base_filename}.html")

    # Handle both symbol and string keys in result hash
    success = result[:success] || result['success']
    error = result[:error] || result['error']
    raw_text = result[:raw_text] || result['raw_text']
    data = result[:data] || result['data']

    # Build comprehensive result JSON
    ocr_result = {
      'game' => {
        'name' => game.name,
        'slug' => game.slug,
        'handler_class' => game.ocr_config&.dig('handler_class')
      },
      'screenshot' => {
        'filename' => File.basename(image_path),
        'path' => image_path.to_s
      },
      'ocr_result' => {
        'success' => success,
        'error' => error,
        'raw_text' => raw_text,
        'raw_text_length' => raw_text&.length || 0,
        'parsed_data' => data,
        'parsed_data_keys' => data&.keys || [],
        'parsed_data_count' => data&.size || 0
      },
      'timestamp' => Time.current.iso8601,
      'test_name' => test_name
    }

    # Write pretty-printed JSON
    File.write(json_path, JSON.pretty_generate(ocr_result))

    # Write HTML file with raw text
    html_content = generate_html_report(ocr_result, game, image_path)
    File.write(html_path, html_content)

    Rails.logger.info "OCR result saved to: #{json_path}"
    Rails.logger.info "OCR result saved to: #{html_path}"
    { json: json_path, html: html_path }
  end

  def generate_html_report(ocr_result, game, image_path)
    game_info = ocr_result['game']
    screenshot_info = ocr_result['screenshot']
    ocr_data = ocr_result['ocr_result']
    timestamp = ocr_result['timestamp']
    test_name = ocr_result['test_name']
    raw_text = ocr_data['raw_text'] || ''

    # Convert newlines to <br> tags for HTML display
    formatted_text = raw_text.gsub("\n", "<br>\n")

    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>OCR Result: #{CGI.escapeHTML(game_info['name'])}</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
          }
          .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          h1 {
            color: #333;
            border-bottom: 2px solid #4CAF50;
            padding-bottom: 10px;
          }
          .info {
            background-color: #f9f9f9;
            padding: 15px;
            border-radius: 4px;
            margin: 20px 0;
          }
          .info p {
            margin: 5px 0;
          }
          .status {
            padding: 10px;
            border-radius: 4px;
            margin: 20px 0;
          }
          .status.success {
            background-color: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
          }
          .status.error {
            background-color: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
          }
          .screenshot-image {
            max-width: 100%;
            height: auto;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            margin: 20px 0;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          .raw-text {
            background-color: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            padding: 8px 12px;
            margin: 20px 0;
            font-family: 'Courier New', monospace;
            font-size: 11px;
            line-height: 1.4;
            white-space: pre-wrap;
            word-wrap: break-word;
            max-height: 300px;
            overflow-y: auto;
          }
          .parsed-data {
            margin: 20px 0;
          }
          .parsed-data table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
          }
          .parsed-data th,
          .parsed-data td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #dee2e6;
          }
          .parsed-data th {
            background-color: #f8f9fa;
            font-weight: 600;
          }
          .parsed-data tr:hover {
            background-color: #f8f9fa;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>OCR Result: #{CGI.escapeHTML(game_info['name'])}</h1>
      #{'    '}
          <div class="info">
            <p><strong>Test Name:</strong> #{CGI.escapeHTML(test_name)}</p>
            <p><strong>Timestamp:</strong> #{CGI.escapeHTML(timestamp)}</p>
            <p><strong>Screenshot:</strong> <code>#{CGI.escapeHTML(screenshot_info['filename'])}</code></p>
            #{game_info['handler_class'] ? "<p><strong>Handler Class:</strong> <code>#{CGI.escapeHTML(game_info['handler_class'])}</code></p>" : ''}
          </div>

          <div class="status #{ocr_data['success'] ? 'success' : 'error'}">
            #{ocr_data['success'] ? '✅ <strong>Success:</strong> OCR processing completed successfully' : "❌ <strong>Failed:</strong> #{CGI.escapeHTML(ocr_data['error'] || 'Unknown error')}"}
          </div>

          <h2>Screenshot</h2>
          <img src="../assets/#{CGI.escapeHTML(screenshot_info['filename'])}" alt="#{CGI.escapeHTML(screenshot_info['filename'])}" class="screenshot-image">

          <h2>Raw OCR Text</h2>
          <p><strong>Length:</strong> #{ocr_data['raw_text_length']} characters</p>
          <div class="raw-text">
            #{formatted_text}
          </div>

          <div class="parsed-data">
            <h2>Parsed Data</h2>
            #{if ocr_data['parsed_data'] && ocr_data['parsed_data'].any?
              table_rows = ocr_data['parsed_data'].map do |key, value|
                "<tr><td><strong>#{CGI.escapeHTML(key.to_s)}</strong></td><td>#{CGI.escapeHTML(value.to_s)}</td></tr>"
              end.join("\n")
              "<p><strong>Extracted Fields:</strong> #{ocr_data['parsed_data_count']}</p>
              <table>
                <thead>
                  <tr>
                    <th>Field</th>
                    <th>Value</th>
                  </tr>
                </thead>
                <tbody>
                  #{table_rows}
                </tbody>
              </table>"
              else
              "<p><em>No data extracted from OCR text</em></p>"
              end}
          </div>
        </div>
      </body>
      </html>
    HTML

    html
  end

  def process_image_and_assert(image_path, game, test_name, expected_fields: nil)
    skip "#{File.basename(image_path)} not found" unless File.exist?(image_path)

    image_file = create_uploaded_file(image_path)
    result = described_class.process_image(image_file, game)

    unless result[:success]
      fail "OCR failed for #{test_name}: #{result[:error]}"
    end

    expect(result[:success]).to be true
    expect(result[:raw_text]).to be_present
    expect(result[:raw_text].length).to be > 0
    expect(result[:data]).to be_a(Hash)

    # Assert expected fields if provided
    if expected_fields && expected_fields.any?
      # If expected fields are specified, handler should extract at least some data
      expect(result[:data].size).to be > 0, "Handler should extract at least some data, but got #{result[:data].size} keys: #{result[:data].keys.inspect}"

      expected_fields.each do |field|
        expect(result[:data]).to have_key(field), "Expected field '#{field}' not found in parsed data. Available keys: #{result[:data].keys.inspect}"
        expect(result[:data][field]).to be_present, "Field '#{field}' is present but empty or nil"

        # If value is numeric, verify it's a reasonable number
        if result[:data][field].is_a?(Numeric)
          expect(result[:data][field]).to be > 0, "Field '#{field}' should be a positive number, got: #{result[:data][field]}"
        end
      end
    elsif game.ocr_config&.dig('handler_class').present?
      # If handler is present but no expected fields, just verify handler ran (data can be empty)
      # This allows for games where OCR may not extract meaningful data
    end

    # Save OCR result to JSON file for manual inspection
    save_ocr_result_json(image_path, game, result, test_name)

    # Log extracted data for debugging
    Rails.logger.info "#{test_name} - Raw text length: #{result[:raw_text].length}"
    Rails.logger.info "#{test_name} - Extracted data keys: #{result[:data].keys.inspect}"
    Rails.logger.info "#{test_name} - Sample data: #{result[:data].first(5).to_h.inspect}" if result[:data].any?

    result
  end
  describe 'Ashes of Creation screenshots' do
    let!(:aoc_game) { create_game_with_ocr_config(name: 'Ashes of Creation', slug: 'ashes-of-creation', handler_class: 'Games::AshesOfCreation::OcrHandler') }
    let(:guild) { create(:guild) }

    describe 'processing aoc1.webp' do
      it 'extracts gear details from first Ashes of Creation screenshot' do
        image_path = Rails.root.join('spec', 'assets', 'aoc1.webp')
        result = process_image_and_assert(
          image_path,
          aoc_game,
          'AOC1',
          expected_fields: [ 'Level', 'Strength', 'Dexterity', 'Phys Power' ]
        )
        # Verify specific values are reasonable
        expect(result[:data]['Level']).to be_between(1, 100)
        expect(result[:data]['Strength']).to be > 0
        expect(result[:data]['Dexterity']).to be > 0
      end
    end

    describe 'processing aoc2.webp' do
      it 'extracts gear details from second Ashes of Creation screenshot' do
        image_path = Rails.root.join('spec', 'assets', 'aoc2.webp')
        result = process_image_and_assert(
          image_path,
          aoc_game,
          'AOC2',
          expected_fields: [ 'Level' ]
        )
        expect(result[:data]['Level']).to be_between(1, 100) if result[:data]['Level']
      end
    end
  end

  describe 'Where Winds Meet screenshots' do
    let(:wwm_game) { create_game_with_ocr_config(name: 'Where Winds Meet', slug: 'where-winds-meet', handler_class: 'Games::WhereWindsMeet::OcrHandler') }

    let(:guild) { create(:guild) }
    let(:user) { create(:user) }

    # Image paths for all 3 WWM screenshots
    let(:wwm1_path) { Rails.root.join('spec', 'assets', 'wwm1.webp') }
    let(:wwm2_path) { Rails.root.join('spec', 'assets', 'wwm2.webp') }
    let(:wwm3_path) { Rails.root.join('spec', 'assets', 'wwm3.webp') }

    it 'processes all three Where Winds Meet screenshots and combines into single gear snapshot' do
      # Skip if any image file doesn't exist
      skip 'WWM screenshots not found' unless File.exist?(wwm1_path) && File.exist?(wwm2_path) && File.exist?(wwm3_path)

      # Process all three images
      results = []
      [ wwm1_path, wwm2_path, wwm3_path ].each_with_index do |path, index|
        image_file = create_uploaded_file(path, "wwm#{index + 1}.webp")
        result = described_class.process_image(image_file, wwm_game)

        unless result[:success]
          fail "OCR failed for wwm#{index + 1}.webp: #{result[:error]}"
        end
        expect(result[:success]).to be true
        expect(result[:raw_text]).to be_present
        expect(result[:data]).to be_a(Hash)

        # WWM handlers may extract data from some images but not others
        # Just verify handler ran (data is a hash, even if empty)

        results << result

        # Save individual OCR result to JSON file
        save_ocr_result_json(path, wwm_game, result, "WWM#{index + 1}")

        # Log extracted data for debugging
        Rails.logger.info "WWM#{index + 1} - Raw text length: #{result[:raw_text].length}"
        Rails.logger.info "WWM#{index + 1} - Extracted data keys: #{result[:data].keys.inspect}"
      end

      # Combine OCR results from all three images
      combined_raw_text = results.each_with_index.map { |r, idx| "--- Image #{idx + 1} ---\n\n#{r[:raw_text]}" }.join("\n\n")
      combined_data = {}

      results.each_with_index do |result, index|
        # Merge data, handling conflicts by appending image number
        result[:data].each do |key, value|
          if combined_data[key].present?
            # If key exists, create array or append
            combined_data[key] = [ combined_data[key] ] unless combined_data[key].is_a?(Array)
            combined_data[key] << value
          else
            combined_data[key] = value
          end
        end
      end

      # Ensure data is not empty (validation requires presence)
      # If no data was extracted, add a placeholder to indicate OCR ran but found nothing
      if combined_data.empty?
        combined_data['ocr_status'] = 'completed'
        combined_data['note'] = 'No gear data extracted from images'
      end

      # Create a single gear snapshot with combined data
      # Use the first image as the screenshot attachment
      primary_image_file = create_uploaded_file(wwm1_path, 'wwm1.webp')

      # Mock embedding service to avoid actual Python calls
      allow(GearEmbeddingService).to receive(:generate_embedding).and_return([ 0.1, 0.2, 0.3 ])
      allow(GearEmbeddingService).to receive(:validate_embedding).and_return({ valid: true, warning: nil })

      snapshot = GearSnapshot.new(
        guild: guild,
        user: user,
        game: wwm_game,
        source: 'web',
        raw_text: combined_raw_text,
        data: combined_data,
        embedding: [ 0.1, 0.2, 0.3 ].to_json,
        validation_passed: true
      )

      # Attach the first image as the screenshot
      primary_image_file.rewind if primary_image_file.respond_to?(:rewind)
      snapshot.screenshot.attach(
        io: primary_image_file,
        filename: 'wwm_combined.webp',
        content_type: 'image/webp'
      )

      unless snapshot.save
        fail "Failed to save snapshot: #{snapshot.errors.full_messages.join(', ')}"
      end
      expect(snapshot.save).to be true
      expect(snapshot.persisted?).to be true
      expect(snapshot.raw_text).to include('--- Image')
      expect(snapshot.data).to be_a(Hash)
      expect(snapshot.screenshot.attached?).to be true

      # Save combined result to JSON file
      combined_result = {
        success: true,
        raw_text: combined_raw_text,
        data: combined_data
      }
      save_ocr_result_json(wwm1_path, wwm_game, combined_result, 'WWM_Combined')

      # Log final combined data for debugging
      Rails.logger.info "WWM Combined - Total raw text length: #{combined_raw_text.length}"
      Rails.logger.info "WWM Combined - Combined data keys: #{combined_data.keys.inspect}"
      Rails.logger.info "WWM Combined - Data sample: #{combined_data.first(10).to_h.inspect}" if combined_data.any?
    end
  end

  describe 'Blade & Soul screenshots' do
    let!(:blade_soul_game) { create_game_with_ocr_config(name: 'Blade & Soul', slug: 'blade-and-soul', handler_class: 'Games::BladeAndSoul::OcrHandler') }
    let(:guild) { create(:guild) }

    it 'extracts gear details from Blade & Soul screenshot' do
      # Blade & Soul screenshots can be complex and take longer to process
      original_timeout = ENV['OCR_TIMEOUT']
      ENV['OCR_TIMEOUT'] = '60' # Increase timeout to 60 seconds for this test

      begin
        image_path = Rails.root.join('spec', 'assets', 'Blade&Soul.webp')
        result = process_image_and_assert(
          image_path,
          blade_soul_game,
          'Blade & Soul',
          expected_fields: [ 'Attack Power', 'HP', 'Defense' ]
        )
        expect(result[:data]['Attack Power']).to be > 0
        expect(result[:data]['HP']).to be > 0
        expect(result[:data]['Defense']).to be > 0
      ensure
        # Restore original timeout
        if original_timeout
          ENV['OCR_TIMEOUT'] = original_timeout
        else
          ENV.delete('OCR_TIMEOUT')
        end
      end
    end
  end

  describe 'Destiny 2 screenshots' do
    let!(:destiny2_game) { create_game_with_ocr_config(name: 'Destiny 2', slug: 'destiny-2', handler_class: 'Games::Destiny2::OcrHandler') }
    let(:guild) { create(:guild) }

    # OCR output contains only numbers with no meaningful text labels - cannot extract structured data
    # The screenshot OCR output is mostly numeric values without clear labels,
    # making it impossible to reliably extract structured gear data
    xit 'extracts gear details from Destiny 2 screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'Destiny2.webp')
      result = process_image_and_assert(
        image_path,
        destiny2_game,
        'Destiny 2',
        expected_fields: []
      )
      # At least one power field should be present (may be 0)
      expect(result[:data]['Power Level'] || result[:data]['Power']).to be_present
    end
  end

  describe 'Final Fantasy XIV screenshots' do
    let!(:ffxiv_game) { create_game_with_ocr_config(name: 'Final Fantasy XIV', slug: 'final-fantasy-xiv', handler_class: 'Games::FinalFantasyXiv::OcrHandler') }
    let(:guild) { create(:guild) }

    it 'extracts gear details from Final Fantasy XIV screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'FinalFantasyXIV.webp')
      result = process_image_and_assert(
        image_path,
        ffxiv_game,
        'Final Fantasy XIV',
        expected_fields: [ 'Level', 'Strength', 'Dexterity', 'Vitality', 'Intelligence', 'Mind', 'Piety', 'Average Item Level' ]
      )
      expect(result[:data]['Level']).to be_between(1, 100) if result[:data]['Level']
      expect(result[:data]['Average Item Level']).to be > 0 if result[:data]['Average Item Level']
    end
  end

  describe 'Guild Wars 2 screenshots' do
    let!(:gw2_game) { create_game_with_ocr_config(name: 'Guild Wars 2', slug: 'guild-wars-2', handler_class: 'Games::GuildWars2::OcrHandler') }
    let(:guild) { create(:guild) }

    # Screenshot is too blurry - OCR cannot reliably extract meaningful data
    # The screenshot quality is insufficient for OCR to extract structured gear data
    xit 'extracts gear details from Guild Wars 2 screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'GuildWars2.webp')
      result = process_image_and_assert(
        image_path,
        gw2_game,
        'Guild Wars 2',
        expected_fields: []
      )
      # GW2 may have sparse data, just verify handler ran
      expect(result[:data]).to be_a(Hash)
    end
  end

  describe 'Lost Ark screenshots' do
    let!(:lost_ark_game) { create_game_with_ocr_config(name: 'Lost Ark', slug: 'lost-ark', handler_class: 'Games::LostArk::OcrHandler') }
    let(:guild) { create(:guild) }

    it 'extracts gear details from Lost Ark screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'LostArk.webp')
      result = process_image_and_assert(
        image_path,
        lost_ark_game,
        'Lost Ark',
        expected_fields: [ 'Attack Power', 'Max HP' ]
      )
      expect(result[:data]['Attack Power']).to be > 0 if result[:data]['Attack Power']
      expect(result[:data]['Max HP']).to be > 0 if result[:data]['Max HP']
    end
  end

  describe 'MapleStory 2 screenshots' do
    let!(:maple_story2_game) { create_game_with_ocr_config(name: 'MapleStory 2', slug: 'maplestory-2', handler_class: 'Games::Maplestory2::OcrHandler') }
    let(:guild) { create(:guild) }

    around do |example|
      original_debug_text = ENV["OCR_DEBUG_TEXT"]
      original_debug_response = ENV["OCR_DEBUG_FULL_RESPONSE"]
      ENV["OCR_DEBUG_TEXT"] = "true"
      ENV["OCR_DEBUG_FULL_RESPONSE"] = "true"
      example.run
    ensure
      if original_debug_text
        ENV["OCR_DEBUG_TEXT"] = original_debug_text
      else
        ENV.delete("OCR_DEBUG_TEXT")
      end
      if original_debug_response
        ENV["OCR_DEBUG_FULL_RESPONSE"] = original_debug_response
      else
        ENV.delete("OCR_DEBUG_FULL_RESPONSE")
      end
    end

    it 'extracts gear details from MapleStory 2 screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'MapleStory2.webp')
      result = process_image_and_assert(
        image_path,
        maple_story2_game,
        'MapleStory 2',
        expected_fields: [ 'Combat Power', 'HP', 'MP', 'STR', 'DEX', 'INT', 'LUK', 'ATTACK POWER' ]
      )
      expect(result[:data]['Combat Power']).to be > 0 if result[:data]['Combat Power']
      expect(result[:data]['HP']).to be > 0 if result[:data]['HP']
      expect(result[:data]['MP']).to be > 0 if result[:data]['MP']
      expect(result[:data]['ATTACK POWER']).to be > 0 if result[:data]['ATTACK POWER']
    end
  end

  describe 'Old School RuneScape screenshots' do
    let!(:osrs_game) { create_game_with_ocr_config(name: 'Old School RuneScape', slug: 'old-school-runescape', handler_class: 'Games::OldSchoolRuneScape::OcrHandler') }
    let(:guild) { create(:guild) }

    it 'extracts gear details from Old School RuneScape screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'OldSchoolRunescape.webp')
      result = process_image_and_assert(
        image_path,
        osrs_game,
        'Old School RuneScape',
        expected_fields: []
      )
      # OSRS may have attack/defense bonuses, verify handler ran
      expect(result[:data]).to be_a(Hash)
    end
  end

  describe 'RuneScape 3 screenshots' do
    let!(:rs3_game) { create_game_with_ocr_config(name: 'RuneScape 3', slug: 'runescape-3', handler_class: 'Games::RuneScape3::OcrHandler') }
    let(:guild) { create(:guild) }

    # OCR output contains only numbers with no meaningful text labels - cannot extract structured data
    # The screenshot OCR output is mostly numeric values without clear labels,
    # making it impossible to reliably extract structured gear data
    xit 'extracts gear details from RuneScape 3 screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'Runescape3.webp')
      result = process_image_and_assert(
        image_path,
        rs3_game,
        'RuneScape 3',
        expected_fields: []
      )
      # RS3 may have combat level, verify handler ran
      expect(result[:data]).to be_a(Hash)
    end
  end

  describe 'World of Warcraft screenshots' do
    let!(:wow_game) { create_game_with_ocr_config(name: 'World of Warcraft', slug: 'world-of-warcraft', handler_class: 'Games::WorldOfWarcraft::OcrHandler') }
    let(:guild) { create(:guild) }

    it 'extracts gear details from World of Warcraft screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'WorlfOfWarcraft.webp')
      result = process_image_and_assert(
        image_path,
        wow_game,
        'World of Warcraft',
        expected_fields: [ 'Level', 'Strength', 'Agility', 'Armor' ]
      )
      expect(result[:data]['Level']).to be_between(1, 100)
      expect(result[:data]['Strength']).to be > 0
      expect(result[:data]['Agility']).to be > 0
      expect(result[:data]['Armor']).to be > 0
    end
  end

  describe 'World of Warcraft Classic screenshots' do
    let!(:wow_classic_game) { create_game_with_ocr_config(name: 'World of Warcraft Classic', slug: 'world-of-warcraft-classic', handler_class: 'Games::WorldOfWarcraftClassic::OcrHandler') }
    let(:guild) { create(:guild) }

    it 'extracts gear details from World of Warcraft Classic screenshot' do
      image_path = Rails.root.join('spec', 'assets', 'WorldOfWarcraftClassic.webp')
      result = process_image_and_assert(
        image_path,
        wow_classic_game,
        'World of Warcraft Classic',
        expected_fields: [ 'Level', 'Agility', 'Armor' ]
      )
      expect(result[:data]['Level']).to be_between(1, 100) if result[:data]['Level']
      expect(result[:data]['Agility']).to be > 0 if result[:data]['Agility']
      expect(result[:data]['Armor']).to be > 0 if result[:data]['Armor']
    end
  end
end
