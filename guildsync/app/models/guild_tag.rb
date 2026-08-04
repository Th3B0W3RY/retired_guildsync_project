class GuildTag < ApplicationRecord
  HEX_COLOR_FORMAT = /\A#(?:[0-9a-fA-F]{6})\z/

  belongs_to :guild
  belongs_to :created_by, class_name: "User", optional: true

  has_many :guild_member_tags, dependent: :destroy
  has_many :guild_members, through: :guild_member_tags

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { scope: :guild_id }
  validates :color, presence: true, format: { with: HEX_COLOR_FORMAT }
end
