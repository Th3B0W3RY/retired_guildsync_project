require "open3"
require "timeout"
require "json"
require "fileutils"

# Ensure Ocr error classes are loaded
require_relative "errors"

module Ocr
  class AzureOcrService < BaseOcrService
    AZURE_OCR_SCRIPT = Rails.root.join("lib", "scripts", "azure_ocr.js").to_s

    class << self
      def extract_text(image_path)
        puts "[AzureOcrService] Starting OCR extraction for image: #{image_path}"

        image_path_str = File.expand_path(image_path.to_s)
        output_file = Rails.root.join("tmp", "azure_ocr_result_#{Time.current.strftime('%Y_%m_%d_%H%M%S')}_#{SecureRandom.hex(16)}.json")
        FileUtils.mkdir_p(File.dirname(output_file))

        validate_inputs!(image_path_str)

        node_cmd = ENV.fetch("GUILDSYNC_NODE_CMD", "node").to_s
        timeout_seconds = ENV.fetch("OCR_TIMEOUT", "30").to_i

        if node_cmd.strip.empty?
          raise Ocr::OcrError, "Node.js command is not set. Set GUILDSYNC_NODE_CMD environment variable."
        end

        puts "[AzureOcrService] Using Node command: #{node_cmd}"
        puts "[AzureOcrService] OCR timeout set to #{timeout_seconds} seconds"
        puts "[AzureOcrService] Output file path: #{output_file}"

        begin
          result_output = +""
          result_error = +""

          args = [ node_cmd, AZURE_OCR_SCRIPT, image_path_str, output_file.to_s ]
          puts "[AzureOcrService] Executing Node command: #{args.join(' ')}"

          result = Timeout.timeout(timeout_seconds) do
            Open3.popen3(*args) do |stdin, stdout, stderr, wait_thr|
              stdin.close

              stdout_thread = Thread.new do
                stdout.each_line do |line|
                  line = line.chomp
                  next if line.empty?
                  result_output << line << "\n"
                  puts "[Azure OCR] #{line}"
                end
              rescue IOError, Errno::EPIPE
                nil
              end

              stderr_thread = Thread.new do
                stderr.each_line do |line|
                  line = line.chomp
                  next if line.empty?
                  result_error << line << "\n"
                  puts "[Azure OCR ERROR] #{line}"
                end
              rescue IOError, Errno::EPIPE
                nil
              end

              stdout_thread.join
              stderr_thread.join
              [ result_output + result_error, wait_thr.value ]
            end
          end

          unless result.last.success?
            Rails.logger.error "Azure OCR script failed with exit code #{result.last.exitstatus}"
            Rails.logger.error "Azure OCR stdout: #{result_output}" unless result_output.empty?
            Rails.logger.error "Azure OCR stderr: #{result_error}" unless result_error.empty?
            raise Ocr::OcrError, "Azure OCR script execution failed: #{result.first.strip.presence || result_error.strip}"
          end

          unless File.exist?(output_file)
            raise Ocr::OcrError, "Azure OCR script did not create output file"
          end

          ocr_result = JSON.parse(File.read(output_file))
          if ocr_result["error"].present?
            raise Ocr::OcrError, "Azure OCR error: #{ocr_result['error']}"
          end

          text = ocr_result["text"].to_s
          puts "[AzureOcrService] Extracted text length: #{text.length} characters"
          puts "[AzureOcrService] Line count: #{ocr_result['line_count'] || 'N/A'}"
          log_debug_payload(ocr_result, text)

          if text.empty?
            raise Ocr::OcrError, "Azure OCR returned no text - image may not contain readable text"
          end

          text
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse Azure OCR JSON response: #{e.message}"
          raise Ocr::OcrError, "Failed to parse Azure OCR response as JSON: #{e.message}"
        rescue Timeout::Error
          raise Ocr::OcrError, "Azure OCR processing timed out after #{timeout_seconds} seconds"
        rescue Errno::ENOENT
          raise Ocr::OcrError, "Node.js executable not found. Set GUILDSYNC_NODE_CMD or ensure node is in PATH."
        end
      ensure
        File.delete(output_file) if output_file && File.exist?(output_file)
      end

      # NOTE: parse_gear_data is now handled by Game model
      # This method is kept for backward compatibility but delegates to game
      def parse_gear_data(raw_text, game = nil)
        if game
          game.parse_gear_data(raw_text)
        else
          data = {}
          raw_text.scan(/([A-Za-z\s]+):\s*([^\n]+)/) do |label, value|
            clean_label = label.strip
            clean_value = value.strip
            data[clean_label] = clean_value unless clean_label.empty?
          end
          data
        end
      end

      private

      def validate_inputs!(image_path)
        unless File.exist?(AZURE_OCR_SCRIPT)
          raise Ocr::OcrError, "Azure OCR script not found at: #{AZURE_OCR_SCRIPT}"
        end

        unless File.exist?(image_path)
          raise Ocr::OcrError, "Image file not found at: #{image_path}"
        end

        unless image_file?(image_path)
          raise Ocr::OcrError, "Input file does not appear to be a supported image"
        end
      end

      def image_file?(path)
        header = File.binread(path, 16)
        return true if header.start_with?("\x89PNG".b) # PNG
        return true if header.start_with?("\xFF\xD8\xFF".b) # JPEG
        return true if header.start_with?("GIF87a".b, "GIF89a".b) # GIF
        return true if header.start_with?("BM".b) # BMP
        return true if header.start_with?("RIFF".b) && header.byteslice(8, 4) == "WEBP".b # WEBP
        return true if header.start_with?("\x00\x00\x01\x00".b) # ICO
        return true if header.start_with?("II*\x00".b, "MM\x00*".b) # TIFF

        false
      rescue
        false
      end

      def log_debug_payload(ocr_result, text)
        return unless truthy_env?("OCR_DEBUG_TEXT")

        puts "[AzureOcrService][DEBUG] OCR text preview start"
        puts text
        puts "[AzureOcrService][DEBUG] OCR text preview end"

        debug_payload = ocr_result["debug"]
        if debug_payload.present?
          puts "[AzureOcrService][DEBUG] OCR debug payload: #{debug_payload.inspect}"
        end
      end

      def truthy_env?(key)
        ENV.fetch(key, "false").to_s.downcase == "true"
      end
    end
  end
end
