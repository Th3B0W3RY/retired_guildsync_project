require 'rtesseract'

# Ensure Ocr error classes are loaded
require_relative 'errors'

module Ocr
  class TesseractOcrService < BaseOcrService
    class << self
      def extract_text(image_path)
        begin
          # Use rtesseract gem to extract text
          # rtesseract can handle various image formats
          image = RTesseract.new(image_path)
          
          # Extract text with basic configuration
          # You can add language options: RTesseract.new(image_path, lang: 'eng')
          text = image.to_s.strip
          
          if text.empty?
            Rails.logger.warn "Tesseract OCR returned empty text for #{image_path}"
            raise Ocr::OcrError, "Tesseract OCR returned no text"
          end
          
          text
        rescue RTesseract::ConversionError => e
          Rails.logger.error "Tesseract conversion error: #{e.message}"
          raise Ocr::OcrError, "Tesseract OCR conversion failed: #{e.message}"
        rescue => e
          Rails.logger.error "Tesseract OCR error: #{e.message}"
          raise Ocr::OcrError, "Tesseract OCR failed: #{e.message}"
        end
      end
      
      # NOTE: parse_gear_data is now handled by Game model
      # This method is kept for backward compatibility but delegates to game
      def parse_gear_data(raw_text, game = nil)
        if game
          game.parse_gear_data(raw_text)
        else
          # Fallback to generic parsing if no game provided
          data = {}
          raw_text.scan(/([A-Za-z\s]+):\s*([^\n]+)/) do |label, value|
            clean_label = label.strip
            clean_value = value.strip
            data[clean_label] = clean_value unless clean_label.empty?
          end
          data
        end
      end
    end
  end
end

