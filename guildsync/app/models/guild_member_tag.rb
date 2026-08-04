class GuildMemberTag < ApplicationRecord
  belongs_to :guild_member
  belongs_to :guild_tag
  belongs_to :assigned_by, class_name: "User", optional: true

  validates :guild_member_id, uniqueness: { scope: :guild_tag_id }
  validate :tag_belongs_to_member_guild

  private

  def tag_belongs_to_member_guild
    return if guild_member.blank? || guild_tag.blank?
    return if guild_member.guild_id == guild_tag.guild_id

    errors.add(:guild_tag, "must belong to the member's guild")
  end
end
