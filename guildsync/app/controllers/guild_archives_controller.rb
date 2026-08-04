# frozen_string_literal: true

class GuildArchivesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_archived_guild, only: [ :unarchive, :destroy ]

  def index
    @archived_guilds = current_user.owned_guilds.archived.order(archived_at: :desc)
  end

  def unarchive
    @guild.unarchive!(actor: current_user)
    redirect_to guild_archives_path, notice: t("guild_archives.alerts.unarchived_success", guild_name: @guild.name)
  rescue ArgumentError
    redirect_to guild_archives_path, alert: t("guild_archives.alerts.unarchive_plan_limit")
  end

  def destroy
    unless @guild.eligible_for_purge?
      redirect_to guild_archives_path, alert: t("guild_archives.alerts.purge_not_ready")
      return
    end

    guild_name = @guild.name
    @guild.purge!
    redirect_to guild_archives_path, notice: t("guild_archives.alerts.purged_success", guild_name: guild_name)
  end

  private

  def set_archived_guild
    @guild = current_user.owned_guilds.archived.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to guild_archives_path, alert: t("guild_archives.alerts.not_found")
  end
end
