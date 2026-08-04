# frozen_string_literal: true

require "tempfile"

class FileCompressionJob
  include Sidekiq::Job

  def perform(file_entry_id)
    file_entry = FileEntry.find_by(id: file_entry_id)
    return unless file_entry&.file&.attached?

    begin
      if file_entry.image?
        compress_image(file_entry)
      elsif file_entry.pdf?
        compress_pdf(file_entry)
      end

      file_entry.update(compressed: true) if file_entry.compressed == false
    rescue => e
      Rails.logger.error "File compression failed for FileEntry #{file_entry_id}: #{e.message}"
      # Don't fail the job, just log the error
    end
  end

  private

  def compress_image(file_entry)
    return unless file_entry.file.attached?

    # Use image_processing gem to create a compressed variant
    variant = file_entry.file.variant(
      resize_to_limit: [1920, 1920],
      quality: 85,
      format: :jpeg
    )

    # Process the variant to ensure it's created
    variant.processed

    # Update size if we can get the new size
    if variant.service.exist?(variant.key)
      blob = ActiveStorage::Blob.find_by(key: variant.key)
      if blob
        file_entry.update(size: blob.byte_size)
      end
    end
  rescue => e
    Rails.logger.warn "Image compression failed for FileEntry #{file_entry.id}: #{e.message}"
    # Fallback: just mark as processed even if compression failed
  end

  def compress_pdf(file_entry)
    # PDF compression requires ghostscript (gs command)
    # This is a fallback - if ghostscript is not available, we skip compression
    return unless system("which", "gs", out: File::NULL, err: File::NULL)
    return unless file_entry.file.attached?

    output_tmp = nil
    begin
      output_tmp = Tempfile.new(["compressed_#{file_entry.id}_", ".pdf"], Rails.root.join("tmp"))
      output_tmp.close

      file_entry.file.open(tmpdir: Rails.root.join("tmp")) do |input_tmp|
        success = system(
          "gs",
          "-sDEVICE=pdfwrite",
          "-dCompatibilityLevel=1.4",
          "-dPDFSETTINGS=/ebook",
          "-dNOPAUSE",
          "-dQUIET",
          "-dBATCH",
          "-sOutputFile=#{output_tmp.path}",
          input_tmp.path,
          out: File::NULL,
          err: File::NULL
        )

        return unless success
        return unless File.exist?(output_tmp.path)
        return unless File.size(output_tmp.path) < input_tmp.size

        File.open(output_tmp.path, "rb") do |compressed_file|
          file_entry.file.attach(
            io: compressed_file,
            filename: file_entry.name,
            content_type: "application/pdf"
          )
        end
        file_entry.update(size: File.size(output_tmp.path))
      end
    ensure
      output_tmp&.close!
    end
  rescue => e
    Rails.logger.warn "PDF compression failed for FileEntry #{file_entry.id}: #{e.message}"
    # Fallback: mark as processed even if compression failed
  end
end
