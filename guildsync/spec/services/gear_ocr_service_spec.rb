# frozen_string_literal: true

# No real OCR API calls: all engine extract_text methods are stubbed so specs never use OCR credits.

require 'rails_helper'

RSpec.describe GearOcrService, :ocr do
  let(:game) { create(:game, ocr_config: {}) }

  # Stub all OCR engines so no real API is ever called (no credits used)
  before do
    stub_text = "Gear Score: 1642\nWeapon 1: Shadowblade"
    allow(Ocr::AzureOcrService).to receive(:extract_text).and_return(stub_text)
    allow(Ocr::SuryaOcrService).to receive(:extract_text).and_return(stub_text)
    allow(Ocr::TesseractOcrService).to receive(:extract_text).and_return(stub_text)
    allow(Ocr::PaddleOcrService).to receive(:extract_text).and_return(stub_text) if defined?(Ocr::PaddleOcrService)
  end

  describe '.process_image' do
    # Create a minimal valid PNG file for testing
    let(:image_file) do
      # Create a 1x1 transparent PNG
      png_data = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, # 1x1 dimensions
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, # Bit depth, color type, etc.
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, # IDAT chunk
        0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, # Image data
        0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, # End of IDAT
        0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82  # IEND chunk
      ].pack('C*')
      
      file = Tempfile.new(['test_image', '.png'])
      file.binmode
      file.write(png_data)
      file.rewind
      
      # Create an ActionDispatch::Http::UploadedFile-like object
      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: file,
        filename: 'test_image.png',
        type: 'image/png'
      )
      uploaded_file
    end
    
    context 'with valid image file' do
      before do
        # Mock OCR service class method to avoid actual Python calls in tests
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return("Gear Score: 1642\nWeapon 1: Shadowblade")
      end
      
      it 'processes image and returns parsed data' do
        result = described_class.process_image(image_file, game)

        expect(result[:success]).to be true
        expect(result[:raw_text]).to be_present
        expect(result[:data]).to be_a(Hash)
        expect(result[:data]['Gear Score']).to eq('1642')
        expect(result[:data]['Weapon 1']).to eq('Shadowblade')
      end
      
      it 'returns success when OCR extracts text' do
        result = described_class.process_image(image_file, game)
        
        expect(result[:success]).to be true
        expect(result[:error]).to be_nil
      end

      it 'drops chat-like OCR lines before stat parse but keeps full raw_text' do
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return(<<~TEXT.strip)
          [Say] PlayerOne: trade?
          Focus: 1695 (4.9%)
        TEXT
        result = described_class.process_image(image_file, game)

        expect(result[:success]).to be true
        expect(result[:raw_text]).to include("PlayerOne")
        expect(result[:data]).to eq("Focus" => "1695 (4.9%)")
      end

      # The service stays lenient when OCR returns text that yields no stat pairs: it succeeds
      # with empty data and keeps raw_text. The "no stats extracted" contract (warning, no clean
      # success) is enforced by GearController#upload so the Discord path is unaffected.
      it 'returns success with empty data when OCR text has no parseable stats' do
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return("the quick brown fox")
        result = described_class.process_image(image_file, game)

        expect(result[:success]).to be true
        expect(result[:raw_text]).to eq("the quick brown fox")
        expect(result[:data]).to eq({})
      end

      it 'extracts a left-panel character sheet and drops chat/system noise (game-agnostic)' do
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return(<<~TEXT.strip)
          Faction: Karanya Alliance
          Honor Points: 445805
          Melee Attack: 2810.64
          The Aegis Island region has fallen into a state of Danger Zone: Stage 5!
          Grimmjow: lets meet at the gate now everyone hurry
        TEXT
        result = described_class.process_image(image_file, game)

        expect(result[:success]).to be true
        expect(result[:data]).to eq(
          "Faction" => "Karanya Alliance",
          "Honor Points" => "445805",
          "Melee Attack" => "2810.64"
        )
      end
    end
    
    context 'with invalid file type' do
      let(:invalid_file) do
        file = Tempfile.new(['test', '.txt'])
        file.write('not an image')
        file.rewind
        
        uploaded_file = ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'test.txt',
          type: 'text/plain'
        )
        uploaded_file
      end
      
      it 'handles invalid images gracefully' do
        result = described_class.process_image(invalid_file, game)
        
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
        expect(result[:error]).to include('Invalid file type')
      end
    end
    
    context 'with file too large' do
      let(:large_file) do
        # Create a file that's larger than 10MB
        file = Tempfile.new(['large', '.png'])
        file.binmode
        file.write('x' * (11.megabytes))
        file.rewind
        
        uploaded_file = ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'large.png',
          type: 'image/png'
        )
        uploaded_file
      end
      
      it 'rejects files that are too large' do
        result = described_class.process_image(large_file, game)
        
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
        expect(result[:error]).to include('too large')
      end
    end
    
    context 'when OCR returns empty text' do
      before do
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return('')
      end
      
      it 'returns error when no text is extracted' do
        result = described_class.process_image(image_file, game)
        
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
        expect(result[:error]).to include('No text could be extracted')
      end
    end
    
    context 'when OCR service raises an error' do
      before do
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_raise(StandardError.new('OCR failed'))
      end
      
      it 'handles OCR errors gracefully' do
        expect(ErrorLogger).to receive(:capture).with(
          instance_of(StandardError),
          hash_including(
            severity: 'high',
            context: hash_including(component: 'GearOcrService.process_image', ocr_engine: described_class::OCR_ENGINE)
          )
        )
        result = described_class.process_image(image_file, game)
        
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context 'when user is at OCR limit (trial monthly hard stop per Ocr::UsageTracker::PLAN_LIMITS)' do
      let(:user_at_limit) do
        u = create(:user)
        # Trial monthly limit is 3; hard_stop == limit, so used >= 3 blocks the next request.
        if User.column_names.include?("ocr_billing_plan")
          u.update_columns(ocr_billing_plan: "trial", ocr_requests_used_this_period: 3)
        end
        u.reload
      end

      before do
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return("") # never call real OCR in this context
      end

      it 'returns error and does not perform OCR when user is at hard stop' do
        skip 'User has no OCR columns' unless User.column_names.include?('ocr_billing_plan')
        result = described_class.process_image(image_file, game, user: user_at_limit)
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
        expect(result[:error]).to match(/max OCR|limit|plan|requests/i)
      end
    end
    
    context 'when member uploads in a guild whose owner pays for the stat scanner' do
      let(:owner_user) { create(:user, skip_free_plan_subscription: true) }
      let(:member_user) { create(:user, skip_free_plan_subscription: true) }
      let(:upgraded_plan) do
        PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
          create(:pricing_plan,
            name: "Upgraded",
            price: 16,
            price_display: "$16",
            period: "per month",
            max_guilds: nil,
            max_members_per_guild: nil,
            active: true,
            display_order: 97)
      end
      let(:free_plan) do
        PricingPlan.where("LOWER(TRIM(name)) = ?", "free").first ||
          create(:pricing_plan, name: "Free", price: 0, max_guilds: 1, max_members_per_guild: 5, active: true, display_order: 1)
      end

      let!(:guild) do
        owner_user.subscribe_to_plan!(upgraded_plan)
        create(:guild, owner: owner_user)
      end

      before do
        member_user.subscribe_to_plan!(free_plan)
        create(:guild_member, guild: guild, user: member_user, status: :active, role: :member)
      end

      it 'increments OCR usage on the guild owner, not the member' do
        skip 'User has no OCR billing columns' unless User.column_names.include?("ocr_billing_plan")

        owner_user.update_columns(
          ocr_billing_plan: "upgraded",
          ocr_requests_used_this_period: 0,
          ocr_last_reset_at: Time.current.beginning_of_month
        )
        member_user.update_columns(ocr_billing_plan: "free", ocr_requests_used_this_period: 0)

        result = described_class.process_image(
          image_file,
          guild.games.first,
          user: member_user,
          guild: guild
        )

        expect(result[:success]).to be true
        expect(owner_user.reload.ocr_requests_used_this_period).to eq(1)
        expect(member_user.reload.ocr_requests_used_this_period).to eq(0)
      end
    end

    context 'with game-specific OCR handler configured' do
      let(:game_with_handler) do
        create(:game, ocr_config: {
          'handler_class' => 'Games::WorldOfWarcraft::OcrHandler'
        })
      end

      before do
        allow(Ocr::AzureOcrService).to receive(:extract_text).and_return("Stamina: 42\nStrength: 10")
      end

      it 'still parses with the universal stat parser (game handlers are not used for uploads)' do
        result = described_class.process_image(image_file, game_with_handler)

        expect(result[:success]).to be true
        expect(result[:data]['Stamina']).to eq('42')
        expect(result[:data]['Strength']).to eq('10')
      end
    end
  end
end

