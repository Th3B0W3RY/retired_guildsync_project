require "fileutils"

class GearOcrService
  OCR_ENGINE = ENV.fetch('OCR_ENGINE', 'azure').downcase
  
  class << self
    # +game+ is retained for call-site compatibility (e.g. DB foreign key on snapshots) but OCR parsing is game-agnostic.
    # +guild+ when present: bill OCR quota to guild owner if their plan includes +:ai_gear_scanner+ (see Ocr::BillingSubject).
    def process_image(image_file, _game, user: nil, request: nil, guild: nil)
      billing_user = user.present? ? Ocr::BillingSubject.for_gear_upload(actor: user, guild: guild) : nil

      # OCR usage limit check (before any work); pass request for IP abuse tracking
      if billing_user.present?
        _, err = Ocr::UsageTracker.check(user: billing_user, amount: 1, request: request)
        if err
          return {
            raw_text: nil,
            data: {},
            success: false,
            error: err.message
          }
        end
      end

      # Validate file type
      unless valid_image_file?(image_file)
        return {
          raw_text: nil,
          data: {},
          success: false,
          error: 'Invalid file type. Please upload a supported image format (PNG, JPEG, WebP, GIF, BMP, TIFF, ICO).'
        }
      end
      
      # Validate file size (10MB max)
      max_size = 10.megabytes
      if image_file.size > max_size
        return {
          raw_text: nil,
          data: {},
          success: false,
          error: "File too large. Maximum size is #{max_size / 1.megabyte}MB."
        }
      end
      
      # Save temporary file
      temp_path = save_temp_image(image_file)

      begin
        # Extract text using configured OCR engine
        Rails.logger.info "Extracting text from image using #{OCR_ENGINE} OCR engine"
        raw_text = ocr_engine.extract_text(temp_path)
        Rails.logger.debug "OCR extracted #{raw_text&.length || 0} characters"
        
        if raw_text.blank?
          Rails.logger.warn "OCR returned empty text - may indicate poor image quality or no text present"
          return {
            raw_text: nil,
            data: {},
            success: false,
            error: 'No text could be extracted from the image. Please ensure the image contains readable text.'
          }
        end
        
        Rails.logger.debug "OCR extracted #{raw_text.length} characters of text"

        stat_text = StatScanner::OcrTextPrefilter.filter_for_stat_scan(raw_text)
        data = StatScanner::UniversalStatParser.parse(stat_text)

        Rails.logger.info "Parsed #{data.keys.size} stat fields from OCR text (universal parser)"
        
        # Count successful OCR only; pass request to record IP/user_agent for abuse tracking
        if billing_user.present?
          initiated_by = (user if user.present? && billing_user.id != user.id)
          Ocr::UsageTracker.increment_after_success!(
            user: billing_user,
            amount: 1,
            request: request,
            initiated_by: initiated_by
          )
        end
        
        {
          raw_text: raw_text,
          data: data,
          success: true
        }
      rescue Ocr::UsageTracker::Blocked => e
        {
          raw_text: nil,
          data: {},
          success: false,
          error: e.message
        }
      rescue => e
        Rails.logger.error "OCR processing failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        ErrorLogger.capture(
          e,
          context: {
            component: "GearOcrService.process_image",
            ocr_engine: OCR_ENGINE,
            user_id: user&.id,
            ocr_billed_user_id: billing_user&.id,
            guild_id: guild&.id
          }.compact,
          severity: "high"
        )
        {
          raw_text: nil,
          data: {},
          success: false,
          error: e.message
        }
      ensure
        FileUtils.rm_f(temp_path.to_s) if temp_path.present? && File.exist?(temp_path.to_s)
      end
    end
    
    private
    
    def ocr_engine
      case OCR_ENGINE
      when 'azure'
        Ocr::AzureOcrService
      when 'surya'
        Ocr::SuryaOcrService
      when 'paddle'
        Ocr::PaddleOcrService # Future implementation
      when 'tesseract'
        Ocr::TesseractOcrService # Fallback
      else
        Ocr::AzureOcrService
      end
    end
    
    def valid_image_file?(image_file)
      return false unless image_file.present?
      
      allowed_types = [
        'image/png',
        'image/jpeg',
        'image/jpg',
        'image/webp',
        'image/gif',
        'image/bmp',
        'image/tiff',
        'image/x-icon',
        'image/vnd.microsoft.icon'
      ]
      content_type = image_file.content_type || (image_file.respond_to?(:content_type_from_file) ? image_file.content_type_from_file : nil)
      return true if allowed_types.include?(content_type)

      filename = if image_file.respond_to?(:original_filename)
        image_file.original_filename.to_s
      elsif image_file.respond_to?(:path)
        image_file.path.to_s
      else
        ""
      end
      extension = File.extname(filename).downcase
      %w[.png .jpg .jpeg .webp .gif .bmp .tif .tiff .ico].include?(extension)
    end
    
    def save_temp_image(image_file)
      expanded = nil
      relative = Rails.root.join("tmp", "ocr_#{SecureRandom.hex(16)}.png")
      FileUtils.mkdir_p(File.dirname(relative))
      expanded = File.expand_path(relative.to_s)

      image_file.rewind if image_file.respond_to?(:rewind)
      image_data = image_file.read

      if image_data.nil? || image_data.empty?
        raise ArgumentError, "Image file appears to be empty"
      end

      File.binwrite(expanded, image_data)

      unless File.exist?(expanded) && File.size(expanded).positive?
        FileUtils.rm_f(expanded)
        raise IOError, "Failed to save temp image file"
      end

      expanded
    rescue StandardError
      FileUtils.rm_f(expanded) if expanded.present? && File.exist?(expanded.to_s)
      raise
    end
  end
end

