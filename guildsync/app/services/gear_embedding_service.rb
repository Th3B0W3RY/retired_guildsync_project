require 'open3'
require 'fileutils'
require 'timeout'
require 'json'

class GearEmbeddingService
  # Threshold for similarity (0.0 to 1.0)
  # Lower threshold = stricter validation
  SIMILARITY_THRESHOLD = ENV.fetch('GEAR_EMBEDDING_THRESHOLD', '0.7').to_f
  
  # Minimum number of reference embeddings needed for validation
  MIN_REFERENCE_SAMPLES = ENV.fetch('GEAR_MIN_REFERENCE_SAMPLES', '10').to_i
  
  class << self
    def generate_embedding(image_file)
      # Use local model via Python script (sentence-transformers with CLIP)
      # This uses open-source CLIP models, no API dependency required
      generate_local_embedding(image_file)
    end
    
    # +game_id+ is accepted for backward compatibility; reference embeddings are pooled across all validated stat snapshots.
    def validate_embedding(new_embedding, game_id = nil)
      # Handle nil/empty embedding
      return { valid: true, warning: nil } unless new_embedding

      # Validate embedding is an array
      unless new_embedding.is_a?(Array) && new_embedding.any?
        Rails.logger.warn "Invalid embedding provided for validation: #{new_embedding.class}"
        return { valid: true, warning: nil }
      end

      reference_embeddings = get_reference_embeddings

      if reference_embeddings.empty?
        Rails.logger.info "No reference embeddings found for stat scanner - skipping validation"
        return { valid: true, warning: nil }
      end

      if reference_embeddings.size < MIN_REFERENCE_SAMPLES
        Rails.logger.info "Insufficient reference samples (#{reference_embeddings.size}) for stat scanner - skipping validation"
        return { valid: true, warning: nil }
      end

      similarities = []
      reference_embeddings.each do |ref_embedding|
        next unless ref_embedding.is_a?(Array) && ref_embedding.any?

        if ref_embedding.size != new_embedding.size
          Rails.logger.debug "Skipping reference embedding with mismatched dimensions (#{ref_embedding.size} vs #{new_embedding.size})"
          next
        end

        similarity = cosine_similarity(new_embedding, ref_embedding)
        similarities << similarity if similarity
      end

      if similarities.empty?
        Rails.logger.warn "All reference embeddings failed similarity comparison for stat scanner"
        return { valid: true, warning: nil }
      end

      max_similarity = similarities.max

      unless max_similarity
        Rails.logger.warn "Max similarity is nil - skipping validation"
        return { valid: true, warning: nil }
      end

      if max_similarity < SIMILARITY_THRESHOLD
        warning = "Your submission seems a bit off. You may want to double check if this image is a readable stats screen. (Similarity: #{(max_similarity * 100).round(1)}%)"
        { valid: false, warning: warning, max_similarity: max_similarity }
      else
        { valid: true, warning: nil, max_similarity: max_similarity }
      end
    end
    
    private
    
    def generate_local_embedding(image_file)
      # Use Python script with local CLIP model (sentence-transformers)
      # This uses open-source CLIP models, no API dependency required
      temp_path = save_temp_image(image_file)
      
      # Generate temp file for JSON output with datetime prefix
      timestamp = Time.current.strftime('%Y_%m_%d_%H%M%S')
      output_file = Rails.root.join('tmp', "embedding_result_#{timestamp}_#{SecureRandom.hex(16)}.json")
      FileUtils.mkdir_p(File.dirname(output_file))
      
      # Use Python from environment variable or default to python3
      # In Docker/production, this should be set to /opt/venv/bin/python3
      python_executable = resolve_embedding_python_executable
      return nil if python_executable.blank?

      # Ensure paths are strings and properly formatted for the OS
      script_path = Rails.root.join('lib', 'scripts', 'generate_embedding.py').to_s
      temp_path_str = temp_path.to_s
      output_file_str = output_file.to_s
      
      timeout_seconds = ENV.fetch('EMBEDDING_TIMEOUT', '60').to_i
      
      begin
        result = Timeout.timeout(timeout_seconds) do
          Open3.capture2e(
            python_executable,
            script_path,
            temp_path_str,
            output_file_str
          )
        end
        
        # Check if script executed successfully
        unless result.last.success?
          error_output = result.first.strip
          Rails.logger.error "Embedding generation script failed: #{error_output}"
          return nil
        end
        
        # Read JSON from output file
        unless File.exist?(output_file)
          Rails.logger.error "Embedding output file not created: #{output_file}"
          return nil
        end
        
        output_content = File.read(output_file)
        
        # Handle empty file
        if output_content.strip.empty?
          Rails.logger.error "Embedding output file is empty"
          return nil
        end
        
        # Check if output file contains an error (JSON object with "error" key)
        if output_content.strip.start_with?('{')
          begin
            error_obj = JSON.parse(output_content)
            if error_obj['error']
              Rails.logger.error "Embedding generation error: #{error_obj['error']}"
              return nil
            end
          rescue JSON::ParserError
            # Not valid JSON, continue to array check
          end
        end
        
        # Validate output looks like JSON array before parsing
        unless output_content.strip.start_with?('[') && output_content.strip.end_with?(']')
          Rails.logger.error "Embedding output does not appear to be valid JSON array: #{output_content[0..100]}"
          return nil
        end
        
        embedding = JSON.parse(output_content)
        
        # Validate embedding is an array
        unless embedding.is_a?(Array)
          Rails.logger.error "Embedding is not an array: #{embedding.class}"
          return nil
        end
        
        # Validate embedding is not empty
        if embedding.empty?
          Rails.logger.error "Embedding array is empty"
          return nil
        end
        
        # Validate embedding contains only numbers
        unless embedding.all? { |v| v.is_a?(Numeric) }
          Rails.logger.error "Embedding contains non-numeric values"
          return nil
        end
        
        # Validate embedding has reasonable dimensions (CLIP-ViT-B-32 produces 512-dim vectors)
        if embedding.size < 10 || embedding.size > 10000
          Rails.logger.warn "Embedding has unusual dimensions (#{embedding.size}), but continuing"
        end
        
        Rails.logger.debug "Generated embedding with #{embedding.size} dimensions"
        embedding
      rescue Timeout::Error
        Rails.logger.error "Embedding generation timed out after #{timeout_seconds} seconds"
        nil
      rescue Errno::ENOENT => e
        Rails.logger.error "Python command not found: #{python_executable}"
        nil
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse embedding JSON: #{e.message}"
        if File.exist?(output_file)
          Rails.logger.error "Output file content: #{File.read(output_file)[0..500]}"
        end
        nil
      ensure
        File.delete(temp_path) if temp_path && File.exist?(temp_path)
        File.delete(output_file) if File.exist?(output_file)
      end
    end
    
    def get_reference_embeddings
      return [] unless defined?(GearSnapshot) && GearSnapshot.table_exists?

      begin
        query = GearSnapshot
          .where.not(embedding: nil)
          .where.not(embedding: "")
          .where(validation_passed: true)
          .where("created_at > ?", 30.days.ago)
          .limit(100)
        
        embeddings = query.pluck(:embedding)
        
        # Parse and validate embeddings
        valid_embeddings = []
        embeddings.each do |embedding_json|
          next if embedding_json.blank?
          
          begin
            parsed = JSON.parse(embedding_json)
            
            # Validate parsed embedding is a valid array of numbers
            if parsed.is_a?(Array) && parsed.any? && parsed.all? { |v| v.is_a?(Numeric) }
              valid_embeddings << parsed
            else
              Rails.logger.debug "Skipping invalid embedding format: #{embedding_json[0..50]}..."
            end
          rescue JSON::ParserError => e
            Rails.logger.debug "Failed to parse embedding JSON: #{e.message}"
            next
          rescue => e
            Rails.logger.debug "Error processing embedding: #{e.message}"
            next
          end
        end
        
        Rails.logger.debug "Retrieved #{valid_embeddings.size} valid reference embeddings for stat scanner"
        valid_embeddings
      rescue => e
        Rails.logger.error "Error retrieving reference embeddings for stat scanner: #{e.message}"
        []
      end
    end
    
    def cosine_similarity(vec1, vec2)
      # Handle nil/empty vectors
      return 0.0 unless vec1 && vec2
      return 0.0 unless vec1.is_a?(Array) && vec2.is_a?(Array)
      return 0.0 unless vec1.any? && vec2.any?
      
      # Handle dimension mismatch
      unless vec1.size == vec2.size
        Rails.logger.debug "Dimension mismatch in cosine similarity: #{vec1.size} vs #{vec2.size}"
        return 0.0
      end
      
      begin
        dot_product = vec1.zip(vec2).sum { |a, b| a * b }
        magnitude1 = Math.sqrt(vec1.sum { |x| x * x })
        magnitude2 = Math.sqrt(vec2.sum { |x| x * x })
        
        # Handle zero magnitude vectors
        return 0.0 if magnitude1.zero? || magnitude2.zero?
        
        similarity = dot_product / (magnitude1 * magnitude2)
        
        # Clamp similarity to valid range [-1, 1] (shouldn't exceed, but safety check)
        similarity.clamp(-1.0, 1.0)
      rescue => e
        Rails.logger.debug "Error calculating cosine similarity: #{e.message}"
        0.0
      end
    end
    
    def resolve_embedding_python_executable
      Guildsync::SafePythonExecutable.resolve!(ENV.fetch("GUILDSYNC_PYTHON_CMD", "python3"))
    rescue Guildsync::SafePythonExecutable::InvalidExecutable => e
      Rails.logger.error "Invalid GUILDSYNC_PYTHON_CMD: #{e.message}"
      nil
    end

    def save_temp_image(image_file)
      # Handle nil/empty image_file
      raise ArgumentError, "image_file cannot be nil" unless image_file
      
      # Generate temp file with datetime prefix for consistency
      timestamp = Time.current.strftime('%Y_%m_%d_%H%M%S')
      temp_path = Rails.root.join('tmp', "embedding_#{timestamp}_#{SecureRandom.hex(16)}.png")
      FileUtils.mkdir_p(File.dirname(temp_path))
      
      begin
        if image_file.respond_to?(:path) && File.exist?(image_file.path)
          FileUtils.cp(image_file.path, temp_path)
        else
          # Rewind file pointer before reading
          image_file.rewind if image_file.respond_to?(:rewind)
          image_data = image_file.read
          
          # Validate we actually read data
          if image_data.nil? || image_data.empty?
            raise ArgumentError, "Image file appears to be empty"
          end
          
          File.binwrite(temp_path, image_data)
        end
        
        # Verify file was created and has content
        unless File.exist?(temp_path) && File.size(temp_path) > 0
          raise IOError, "Failed to save temp image file"
        end
        
        temp_path.to_s
      rescue => e
        # Cleanup on error
        File.delete(temp_path) if File.exist?(temp_path)
        Rails.logger.error "Failed to save temp image: #{e.message}"
        raise
      end
    end
  end
end

