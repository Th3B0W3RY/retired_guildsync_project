class AllianceTag < ApplicationRecord
  HEX_COLOR_FORMAT = /\A#(?:[0-9a-fA-F]{6})\z/

  belongs_to :alliance
  belongs_to :created_by, class_name: "User", optional: true

  has_many :alliance_member_tags, dependent: :destroy
  has_many :alliance_members, through: :alliance_member_tags

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { scope: :alliance_id }
  validates :color, presence: true, format: { with: HEX_COLOR_FORMAT }
end
