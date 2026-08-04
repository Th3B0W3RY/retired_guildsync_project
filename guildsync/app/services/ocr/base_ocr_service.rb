# Ensure Ocr error classes are loaded
require_relative 'errors'

module Ocr
  class BaseOcrService
    class << self
      def extract_text(image_path)
        raise NotImplementedError, "Subclasses must implement extract_text"
      end
      
      def parse_gear_data(raw_text)
        raise NotImplementedError, "Subclasses must implement parse_gear_data"
      end
    end
  end
end

