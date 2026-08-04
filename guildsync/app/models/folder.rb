class Folder < ApplicationRecord
  include SoftDeletable

  belongs_to :guild
  belongs_to :parent_folder, class_name: "Folder", optional: true

  has_many :subfolders, class_name: "Folder", foreign_key: "parent_folder_id", dependent: :destroy
  has_many :file_entries, dependent: :nullify

  soft_delete_metadata display: :name, search: [ :name ]

  before_destroy :purge_children_including_deleted

  validates :name, presence: true, length: { minimum: 1, maximum: 255 }

  scope :root_folders, -> { where(parent_folder_id: nil) }
  scope :ordered, -> { order(:name) }

  def has_contents?
    subfolders.exists? || file_entries.exists?
  end

  def total_files_count
    file_entries.count + subfolders.sum(&:total_files_count)
  end

  def ancestors
    result = []
    current = parent_folder
    while current
      result << current
      current = current.parent_folder
    end
    result
  end

  private

  def purge_children_including_deleted
    Folder.unscoped.where(parent_folder_id: id).find_each(&:destroy!)
    FileEntry.unscoped.where(folder_id: id).find_each(&:destroy!)
  end
end
