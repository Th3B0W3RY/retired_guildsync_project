class FileEntry < ApplicationRecord
  include SoftDeletable

  belongs_to :guild
  belongs_to :folder, optional: true
  belongs_to :uploader, class_name: "User", foreign_key: "uploaded_by"

  has_one_attached :file

  soft_delete_metadata display: :name, search: [ :name, :content_type ]

  before_destroy :purge_attached_file

  validates :name, presence: true, length: { minimum: 1, maximum: 255 }
  validates :uploaded_by, presence: true

  scope :root_files, -> { where(folder_id: nil) }
  scope :ordered, -> { order(:name) }

  after_commit :update_file_metadata, on: :create
  after_commit :enqueue_compression_job, on: :create, if: -> { file.attached? && compressible? }

  def formatted_size
    return "0 B" if size.nil? || size == 0

    units = [ "B", "KB", "MB", "GB", "TB" ]
    size_in_bytes = size.to_f
    unit_index = 0

    while size_in_bytes >= 1024 && unit_index < units.length - 1
      size_in_bytes /= 1024
      unit_index += 1
    end

    "#{size_in_bytes.round(2)} #{units[unit_index]}"
  end

  def image?
    content_type&.start_with?("image/")
  end

  def video?
    content_type&.start_with?("video/")
  end

  def pdf?
    content_type == "application/pdf"
  end

  def zip?
    content_type == "application/zip" || content_type == "application/x-zip-compressed"
  end

  def compressible?
    image? || pdf?
  end

  private

  def purge_attached_file
    file.purge if file.attached?
  end

  def update_file_metadata
    return unless file.attached?

    blob = file.blob
    update_columns(
      size: blob.byte_size,
      content_type: blob.content_type
    ) if blob
  end

  def enqueue_compression_job
    FileCompressionJob.perform_async(id)
  end
end
