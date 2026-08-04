class AllianceMemberTag < ApplicationRecord
  belongs_to :alliance_member
  belongs_to :alliance_tag
  belongs_to :assigned_by, class_name: "User", optional: true

  validates :alliance_member_id, uniqueness: { scope: :alliance_tag_id }
  validate :tag_belongs_to_member_alliance

  private

  def tag_belongs_to_member_alliance
    return if alliance_member.blank? || alliance_tag.blank?
    return if alliance_member.alliance_id == alliance_tag.alliance_id

    errors.add(:alliance_tag, "must belong to the member's alliance")
  end
end
