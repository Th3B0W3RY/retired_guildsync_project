# frozen_string_literal: true

module Admin
  class GuildTransfersController < BaseController
    GUILD_TRANSFERS_NEW_MAIN_FRAME = "admin_guild_transfers_new_main"

    def new
      @guild = Guild.find(params[:guild_id])
      @users = User.order(:email)
      return render("guild_transfers_new_frame", layout: false) if request.headers["Turbo-Frame"] == GUILD_TRANSFERS_NEW_MAIN_FRAME
    end

    def create
      @guild = Guild.find(params[:guild_id])
      new_owner = User.find(params[:new_owner_id])
      cancel_billing = Array.wrap(params[:cancel_previous_owner_billing]).include?("1")

      result = GuildOwnershipTransferService.call(
        guild: @guild,
        new_owner: new_owner,
        cancel_previous_owner_billing: cancel_billing
      )

      log_admin_action(
        action: "transfer_guild_ownership",
        record: @guild,
        changes_data: {
          old_owner_id: result.old_owner.id,
          new_owner_id: new_owner.id,
          cancel_previous_owner_billing: cancel_billing,
          billing_outcome: result.billing_outcome.to_s,
          billing_mode: result.billing_mode&.to_s,
          billing_error: result.billing_error
        }.compact
      )

      notice = transfer_notice(result)
      respond_to do |format|
        format.html { redirect_to admin_user_path(new_owner), notice: notice }
        format.turbo_stream { redirect_to admin_user_path(new_owner), notice: notice, status: :see_other }
      end
    end

    private

    def transfer_notice(result)
      parts = [ I18n.t("admin.guild_transfers.flash.transferred") ]
      case result.billing_outcome
      when :not_requested
        nil
      when :skipped_still_owns_guilds
        parts << I18n.t("admin.guild_transfers.flash.billing_skipped_still_owns_guilds")
      when :no_subscription
        parts << I18n.t("admin.guild_transfers.flash.billing_none")
      when :applied
        mode_label = I18n.t(
          "admin.guild_transfers.billing_modes.#{result.billing_mode}",
          default: result.billing_mode.to_s.tr("_", " ")
        )
        parts << I18n.t("admin.guild_transfers.flash.billing_applied", mode: mode_label)
      when :failed
        parts << I18n.t("admin.guild_transfers.flash.billing_failed", message: result.billing_error)
      end
      parts.compact.join(" ")
    end
  end
end

