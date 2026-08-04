module Ocr
  module Errors
    class Error < StandardError; end
    class OcrError < Error; end
    class ImageProcessingError < Error; end
  end
  
  # Keep backwards compatible aliases
  Error = Errors::Error
  OcrError = Errors::OcrError
  ImageProcessingError = Errors::ImageProcessingError
end

