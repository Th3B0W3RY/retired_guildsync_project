# frozen_string_literal: true

# Records alliance-scoped activity for the Alliance Activity Feed (60-day retention).
# Only three buckets: HTML hub page views (active members), invite responses by invited guild owners
# (not yet members), and management actions (alliance leader, guild owners in the alliance, or custom
# alliance-privileged roles). No logging for flows outside the alliance hub (e.g. per-guild join requests).
class AllianceActivityLogger
  class << self
    def guild_context_metadata(guild)
      return {} unless guild
      # Best-effort label; Discord API name sync may be added later.
      { discord_server_name: guild.name.to_s }
    end

    # @param view_action [Boolean] HTML hub GET views — active alliance members only.
    # @param invite_response [Boolean] Invited guild owner accepting/declining before membership.
    # @param member_required [Boolean] When false with invite_response false, skips active-member check
    #   (unused in current app; kept for backward compatibility).
    def log(alliance:, action_type:, description:, user: nil, guild: nil, member_required: true,
            view_action: false, invite_response: false, **metadata)
      return unless alliance.present? && alliance.persisted?

      if view_action
        return if user.blank?
        return unless AllianceActivityPolicy.active_alliance_member?(alliance, user)
      elsif invite_response
        return if user.blank?
      else
        return if user.blank?
        if member_required
          return unless AllianceActivityPolicy.active_alliance_member?(alliance, user)
        end
        return unless AllianceActivityPolicy.management_actor?(alliance, user)
      end

      meta = metadata.slice(:discord_server_name, :target_name, :title, :name, :reason, :page).compact
      AllianceActivityLog.create!(
        alliance_id: alliance.id,
        user_id: user&.id,
        guild_id: guild&.id,
        action_type: action_type.to_s,
        description: description.to_s.truncate(500),
        metadata: meta
      )
    rescue => e
      Rails.logger.warn("AllianceActivityLogger failed: #{e.message}")
    end
  end
end
