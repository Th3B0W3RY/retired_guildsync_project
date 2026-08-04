require "open3"
require "timeout"
require "json"
require "fileutils"

# Ensure Ocr error classes are loaded
require_relative "errors"

module Ocr
  class SuryaOcrService < BaseOcrService
    SURYA_SCRIPT = Rails.root.join("lib", "scripts", "surya_ocr.py").to_s

    class << self
      def extract_text(image_path)
        puts "[SuryaOcrService] Starting OCR extraction for image: #{image_path}"

        # Log original image file size
        if File.exist?(image_path)
          file_size = File.size(image_path)
          puts "[SuryaOcrService] Original image file size: #{file_size} bytes (#{(file_size / 1024.0 / 1024.0).round(2)} MB)"
        end

        # Preprocess image (grayscale, threshold) - can be skipped via environment variable
        # Note: Preprocessing converts to grayscale and applies 50% threshold (binary black/white)
        # This does NOT resize/downscale the image - it only changes colorspace
        skip_preprocessing = ENV.fetch('SKIP_OCR_PREPROCESSING', 'false').downcase == 'true'
        if skip_preprocessing
          puts "[SuryaOcrService] Skipping image preprocessing (SKIP_OCR_PREPROCESSING=true)"
          puts "[SuryaOcrService] Using original image without grayscale/threshold conversion"
          preprocessed_path = image_path
        else
          puts "[SuryaOcrService] Preprocessing image (grayscale + 50% threshold)..."
          preprocessed_path = preprocess_image(image_path)
          puts "[SuryaOcrService] Preprocessed image path: #{preprocessed_path}"
          
          # Log preprocessed image file size if different from original
          if preprocessed_path != image_path && File.exist?(preprocessed_path)
            preprocessed_size = File.size(preprocessed_path)
            puts "[SuryaOcrService] Preprocessed image file size: #{preprocessed_size} bytes (#{(preprocessed_size / 1024.0 / 1024.0).round(2)} MB)"
          end
        end

        # Generate temp file for JSON output with datetime prefix
        timestamp = Time.current.strftime("%Y_%m_%d_%H%M%S")
        output_file = Rails.root.join("tmp", "ocr_result_#{timestamp}_#{SecureRandom.hex(16)}.json")
        FileUtils.mkdir_p(File.dirname(output_file))
        puts "[SuryaOcrService] Output file path: #{output_file}"

        # Use Python from environment variable or default to python3
        # In Docker/production, this should be set to /opt/venv/bin/python3
        python_executable = resolve_surya_python_executable
        puts "[SuryaOcrService] Using Python command: #{python_executable}"
        # Ensure paths are strings and properly formatted for the OS
        # On Windows, normalize paths to use forward slashes for Python compatibility
        script_path = File.expand_path(SURYA_SCRIPT.to_s)
        preprocessed_path_str = File.expand_path(preprocessed_path.to_s)
        output_file_str = File.expand_path(output_file.to_s)

        puts "[SuryaOcrService] Expanded script path: #{script_path}"
        puts "[SuryaOcrService] Expanded preprocessed path: #{preprocessed_path_str}"
        puts "[SuryaOcrService] Expanded output path: #{output_file_str}"

        # Normalize paths for cross-platform compatibility
        # Python on Windows can handle forward slashes, and this avoids issues with backslashes
        script_path = script_path.gsub("\\", "/")
        preprocessed_path_str = preprocessed_path_str.gsub("\\", "/")
        output_file_str = output_file_str.gsub("\\", "/")

        puts "[SuryaOcrService] Normalized script path: #{script_path}"
        puts "[SuryaOcrService] Normalized preprocessed path: #{preprocessed_path_str}"
        puts "[SuryaOcrService] Normalized output path: #{output_file_str}"

        # Validate preprocessed_path is not nil or empty
        if preprocessed_path_str.nil? || preprocessed_path_str.strip.empty?
          Rails.logger.error "SuryaOcrService: Preprocessed image path is invalid (nil or empty)"
          raise Ocr::OcrError, "Preprocessed image path is invalid"
        end

        # Validate script path exists (use original path for File.exist? check)
        unless File.exist?(SURYA_SCRIPT.to_s)
          Rails.logger.error "SuryaOcrService: OCR script not found at: #{SURYA_SCRIPT}"
          raise Ocr::OcrError, "OCR script not found at: #{SURYA_SCRIPT}"
        end

        # Validate preprocessed image exists (use original path for File.exist? check)
        unless File.exist?(preprocessed_path)
          Rails.logger.error "SuryaOcrService: Preprocessed image file not found at: #{preprocessed_path}"
          raise Ocr::OcrError, "Preprocessed image file not found at: #{preprocessed_path}"
        end

        # Call Surya OCR via Python script with timeout
        timeout_seconds = ENV.fetch("OCR_TIMEOUT", "30").to_i
        puts "[SuryaOcrService] OCR timeout set to #{timeout_seconds} seconds"

        begin
          puts "[SuryaOcrService] Resolved Python command: #{python_cmd}"

          # Use Open3.popen3 to get separate stdout/stderr streams
          result_output = ""
          result_error = ""
          exit_status = nil

          # Use Python's -u flag for unbuffered output so logs appear immediately
          # File paths (script, image, output) are normalized to forward slashes for Python compatibility
          # Python executable path stays in native format for the OS
          python_args = [ python_executable, "-u", script_path, preprocessed_path_str, output_file_str ]
          puts "[SuryaOcrService] Executing Python command: #{python_args.join(' ')}"

          result = Timeout.timeout(timeout_seconds) do
            Open3.popen3(python_executable, "-u", script_path, preprocessed_path_str, output_file_str) do |stdin, stdout, stderr, wait_thr|
              # Close stdin immediately (we don't need to send input)
              stdin.close

              puts "[SuryaOcrService] Python process started, reading stdout/stderr..."

              # Read stdout and stderr
              stdout_thread = Thread.new do
                begin
                  stdout.each_line do |line|
                    line = line.chomp
                    next if line.empty?
                    result_output << line << "\n"
                    # Log Python script output to console in real-time
                    puts "[Surya OCR] #{line}"
                  end
                rescue IOError, Errno::EPIPE
                  # Stream closed, process likely finished - normal
                  puts "[SuryaOcrService] stdout stream closed"
                rescue => e
                  Rails.logger.error "OCR: Error reading stdout: #{e.class}: #{e.message}"
                end
              end

              stderr_thread = Thread.new do
                begin
                  stderr.each_line do |line|
                    line = line.chomp
                    next if line.empty?
                    result_error << line << "\n"
                    # Log Python script errors to console in real-time
                    puts "[Surya OCR ERROR] #{line}"
                  end
                rescue IOError, Errno::EPIPE
                  # Stream closed, process likely finished - normal
                  puts "[SuryaOcrService] stderr stream closed"
                rescue => e
                  Rails.logger.error "OCR: Error reading stderr: #{e.class}: #{e.message}"
                end
              end

              # Wait for both threads to finish reading
              stdout_thread.join
              stderr_thread.join

              puts "[SuryaOcrService] Finished reading stdout/stderr, waiting for process..."

              # Wait for process to complete
              exit_status = wait_thr.value

              puts "[SuryaOcrService] Python process exited with status: #{exit_status.exitstatus}"

              # Return combined output for compatibility
              [ result_output + result_error, exit_status ]
            end
          end

          # Check if script executed successfully
          unless result.last.success?
            error_output = result.first.strip
            Rails.logger.error "Surya OCR script failed with exit code #{result.last.exitstatus}"
            Rails.logger.error "Surya OCR stdout: #{result_output}" unless result_output.empty?
            Rails.logger.error "Surya OCR stderr: #{result_error}" unless result_error.empty?
            raise Ocr::OcrError, "OCR script execution failed: #{error_output.empty? ? result_error : error_output}"
          end

          puts "[SuryaOcrService] Python script executed successfully"

          # Read JSON from output file
          unless File.exist?(output_file)
            Rails.logger.error "SuryaOcrService: OCR output file not created: #{output_file}"
            raise Ocr::OcrError, "OCR script did not create output file"
          end

          puts "[SuryaOcrService] Reading output file: #{output_file}"
          output_content = File.read(output_file)
          puts "[SuryaOcrService] Output file size: #{output_content.length} bytes"

          # Validate output looks like JSON before parsing
          unless output_content.strip.start_with?("{") && output_content.strip.end_with?("}")
            Rails.logger.error "SuryaOcrService: OCR output does not appear to be valid JSON: #{output_content[0..100]}"
            raise Ocr::OcrError, "OCR script returned invalid output format (expected JSON)"
          end

          # Parse JSON response
          puts "[SuryaOcrService] Parsing JSON response..."
          ocr_result = JSON.parse(output_content)
          puts "[SuryaOcrService] JSON parsed successfully. Keys: #{ocr_result.keys.inspect}"

          # Check for error in response
          if ocr_result["error"]
            Rails.logger.error "SuryaOcrService: Surya OCR error in response: #{ocr_result['error']}"
            raise Ocr::OcrError, "Surya OCR error: #{ocr_result['error']}"
          end

          # Extract text
          text = ocr_result["text"] || ""
          puts "[SuryaOcrService] Extracted text length: #{text.length} characters"
          puts "[SuryaOcrService] Line count: #{ocr_result['line_count'] || 'N/A'}"

          if text.empty?
            Rails.logger.warn "SuryaOcrService: Surya OCR returned empty text for #{image_path}"
            raise Ocr::OcrError, "Surya OCR returned no text - image may not contain readable text"
          end

          puts "[SuryaOcrService] OCR extraction completed successfully"
          text
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse OCR JSON response: #{e.message}"
          if File.exist?(output_file)
            Rails.logger.error "Output file content: #{File.read(output_file)[0..500]}"
          end
          raise Ocr::OcrError, "Failed to parse OCR response as JSON: #{e.message}"
        rescue Timeout::Error
          Rails.logger.error "Surya OCR timed out after #{timeout_seconds} seconds"
          raise Ocr::OcrError, "OCR processing timed out after #{timeout_seconds} seconds"
        rescue Errno::ENOENT => e
          Rails.logger.error "Python command not found: #{python_executable}"
          raise Ocr::OcrError, "Python interpreter not found. Set GUILDSYNC_PYTHON_CMD environment variable or ensure python3 is in PATH"
        rescue => e
          # Catch any other errors from Open3 (including Windows-specific errors)
          Rails.logger.error "OCR processing failed: #{e.message}"

          # Provide helpful error message based on error type
          if e.message.include?("Invalid Parameter") || e.message.include?("no implicit conversion")
            raise Ocr::OcrError, "Python command or path is invalid. Set GUILDSYNC_PYTHON_CMD to a valid Python executable path."
          else
            raise Ocr::OcrError, "OCR processing failed: #{e.message}"
          end
        ensure
          # Cleanup preprocessed image (if different from original)
          if preprocessed_path && preprocessed_path != image_path && File.exist?(preprocessed_path)
            File.delete(preprocessed_path)
          end

          # Cleanup output file
          if File.exist?(output_file)
            File.delete(output_file)
          end
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

      private

      def resolve_surya_python_executable
        Guildsync::SafePythonExecutable.resolve!(ENV.fetch("GUILDSYNC_PYTHON_CMD", "python3"))
      rescue Guildsync::SafePythonExecutable::InvalidExecutable => e
        Rails.logger.error "SuryaOcrService: Invalid GUILDSYNC_PYTHON_CMD: #{e.message}"
        raise Ocr::OcrError, "Invalid Python command. Set GUILDSYNC_PYTHON_CMD to a single executable path or name (no shell metacharacters)."
      end

      def preprocess_image(image_path)
        puts "[SuryaOcrService#preprocess_image] Starting preprocessing for: #{image_path}"

        # Ensure image_path is a string
        image_path_str = image_path.to_s
        puts "[SuryaOcrService#preprocess_image] Image path string: #{image_path_str}"

        # Validate input path exists
        unless File.exist?(image_path_str)
          Rails.logger.warn "SuryaOcrService#preprocess_image: Image path does not exist: #{image_path_str} - using as-is"
          return image_path_str
        end

        file_size = File.size(image_path_str)
        puts "[SuryaOcrService#preprocess_image] Image file exists, size: #{file_size} bytes"

        # Use image_processing gem or ImageMagick
        # Convert to grayscale, apply threshold
        output_path = "#{image_path_str}.preprocessed.png"
        puts "[SuryaOcrService#preprocess_image] Output path will be: #{output_path}"

        # ImageMagick preprocessing (optional - Surya OCR works fine without it)
        # On Windows, avoid using 'convert' as it conflicts with Windows system utility
        # ImageMagick 7+ uses 'magick' command instead
        imagemagick_cmd = nil
        puts "[SuryaOcrService#preprocess_image] Detecting ImageMagick command..."

        if Gem.win_platform?
          # On Windows, check for 'magick' command first (ImageMagick 7+)
          # Then check for ImageMagick's convert in common locations
          puts "[SuryaOcrService#preprocess_image] Checking for ImageMagick on Windows..."
          if system("where", "magick", out: File::NULL, err: File::NULL)
            imagemagick_cmd = "magick"
            puts "[SuryaOcrService#preprocess_image] Found ImageMagick command: magick"
          elsif File.exist?("C:\\Program Files\\ImageMagick-7\\magick.exe")
            imagemagick_cmd = "C:\\Program Files\\ImageMagick-7\\magick.exe"
            puts "[SuryaOcrService#preprocess_image] Found ImageMagick at: C:\\Program Files\\ImageMagick-7\\magick.exe"
          elsif File.exist?("C:\\Program Files (x86)\\ImageMagick-7\\magick.exe")
            imagemagick_cmd = "C:\\Program Files (x86)\\ImageMagick-7\\magick.exe"
            puts "[SuryaOcrService#preprocess_image] Found ImageMagick at: C:\\Program Files (x86)\\ImageMagick-7\\magick.exe"
          else
            puts "[SuryaOcrService#preprocess_image] ImageMagick not found on Windows"
          end
          # Don't use 'convert' on Windows - it's a system utility, not ImageMagick
        else
          # On Unix, check for 'magick' (ImageMagick 7+) or 'convert' (ImageMagick 6)
          puts "[SuryaOcrService#preprocess_image] Checking for ImageMagick on Unix..."
          if system("which", "magick", out: File::NULL, err: File::NULL)
            imagemagick_cmd = "magick"
            puts "[SuryaOcrService#preprocess_image] Found ImageMagick command: magick"
          elsif system("which", "convert", out: File::NULL, err: File::NULL)
            # Verify it's actually ImageMagick by checking version
            # Windows convert.exe would fail with -version
            puts "[SuryaOcrService#preprocess_image] Found 'convert' command, verifying it's ImageMagick..."
            test_result, = Open3.capture2("convert", "-version")
            test_result = test_result.to_s
            if test_result.include?("ImageMagick") || test_result.include?("Version: ImageMagick")
              imagemagick_cmd = "convert"
              puts "[SuryaOcrService#preprocess_image] Verified 'convert' is ImageMagick"
            else
              puts "[SuryaOcrService#preprocess_image] 'convert' is not ImageMagick"
            end
          else
            puts "[SuryaOcrService#preprocess_image] ImageMagick not found on Unix"
          end
        end

        if imagemagick_cmd
          # For Windows system calls, ensure paths use native format (backslashes)
          if Gem.win_platform?
            native_input_path = File.expand_path(image_path_str).gsub("/", "\\")
            native_output_path = File.expand_path(output_path).gsub("/", "\\")
          else
            native_input_path = image_path_str
            native_output_path = output_path
          end

          # Use standard ImageMagick syntax for grayscale conversion
          # -colorspace Gray converts to grayscale
          # -threshold 50% converts to binary (black/white) for better OCR
          success =
            case imagemagick_cmd
            when "magick"
              system("magick", native_input_path, "-colorspace", "Gray", "-threshold", "50%", native_output_path)
            when "convert"
              system("convert", native_input_path, "-colorspace", "Gray", "-threshold", "50%", native_output_path)
            when "C:\\Program Files\\ImageMagick-7\\magick.exe"
              system("C:\\Program Files\\ImageMagick-7\\magick.exe", native_input_path, "-colorspace", "Gray", "-threshold", "50%", native_output_path)
            when "C:\\Program Files (x86)\\ImageMagick-7\\magick.exe"
              system("C:\\Program Files (x86)\\ImageMagick-7\\magick.exe", native_input_path, "-colorspace", "Gray", "-threshold", "50%", native_output_path)
            else
              false
            end

          # Execute command
          puts "[SuryaOcrService#preprocess_image] Executing ImageMagick via #{imagemagick_cmd.inspect}"

          if success && File.exist?(output_path)
            puts "[SuryaOcrService#preprocess_image] Image preprocessing successful, output: #{output_path}"
            # Return path in forward-slash format for Python compatibility
            return output_path
          else
            puts "[SuryaOcrService#preprocess_image] ImageMagick command failed or output file not created"
          end
        else
          # ImageMagick not available - this is fine, preprocessing is optional
          # Surya OCR works well without preprocessing
          puts "[SuryaOcrService#preprocess_image] ImageMagick not found - skipping image preprocessing (optional)"
        end

        # Always return a valid path (original if preprocessing failed)
        puts "[SuryaOcrService#preprocess_image] Returning image path: #{image_path_str}"
        image_path_str
      rescue => e
        Rails.logger.warn "Image preprocessing failed: #{e.message} - using original image"
        puts "[SuryaOcrService#preprocess_image] Preprocessing error: #{e.message} - using original image"
        image_path.to_s
      end
    end
  end
end
