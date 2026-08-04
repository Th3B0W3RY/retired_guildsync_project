# frozen_string_literal: true

# One-line guild activity feed entries for successful stat scanner uploads (web + Discord).
class GearStatScanActivityLog
  class << self
    def log_successful_upload(guild:, initiated_by:, game_name:)
      return unless guild && initiated_by

      billing = Ocr::BillingSubject.for_gear_upload(actor: initiated_by, guild: guild)
      description = if billing.id == initiated_by.id
        I18n.t("gear.activity.uploaded", game: game_name)
      else
        I18n.t("gear.activity.uploaded_shared_guild_plan", game: game_name, leader_name: billing.display_name)
      end

      GuildActivityLogger.log(
        guild: guild,
        user: initiated_by,
        action_type: "gear_uploaded",
        description: description,
        ocr_billed_to_name: (billing.display_name if billing.id != initiated_by.id)
      )
    end
  end
end
