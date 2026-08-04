class LootRollsController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :ensure_guild_member
  before_action :set_loot_roll, only: [:show, :close, :force_reroll, :destroy]
  before_action :authorize_create, only: [:new, :create]
  before_action :authorize_manage, only: [:close, :force_reroll, :destroy]

  def index
    preserve_session
    authorize @guild, :show?
    @loot_rolls = @guild.loot_rolls.includes(:creator, :loot_roll_entries).ordered
  end

  def new
    preserve_session
    @loot_roll = @guild.loot_rolls.build
    @discord_setting = @guild.guild_discord_setting
    @channels = fetch_discord_channels if @discord_setting&.connected?
    @synced_roles = @guild.discord_role_syncs.order(:role_name)

    # Check if loot rolls channel is configured
    unless @discord_setting&.loot_rolls_channel_configured?
      flash.now[:alert] = t('controllers.loot_rolls.channel_required')
    end
  end

  def create
    preserve_session
    @loot_roll = @guild.loot_rolls.build(loot_roll_params)
    @loot_roll.creator = current_user
    @loot_roll.allowed_role_ids = (params[:allowed_role_ids] || []).uniq

    # Use loot_rolls_channel_id from guild settings
    discord_setting = @guild.guild_discord_setting
    unless discord_setting&.loot_rolls_channel_configured?
      @discord_setting = discord_setting
      @channels = fetch_discord_channels if @discord_setting&.connected?
      @synced_roles = @guild.discord_role_syncs.order(:role_name)
      flash.now[:alert] = t('controllers.loot_rolls.channel_must_configure')
      render :new, status: :unprocessable_entity
      return
    end

    @loot_roll.discord_channel_id = discord_setting.loot_rolls_channel_id

    if @loot_roll.save
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "loot_roll_created", description: "Created loot roll \"#{@loot_roll.title}\"", subject: @loot_roll, title: @loot_roll.title)
      session.save if session.respond_to?(:save)

      # Auto-post to Discord (mandatory)
      begin
        service = DiscordLootRollService.new(@loot_roll)
        service.post_loot_roll
        redirect_to guild_loot_roll_path(@guild, @loot_roll), notice: t('controllers.loot_rolls.created_discord')
      rescue => e
        Rails.logger.error "Failed to post loot roll to Discord: #{e.message}"
        redirect_to guild_loot_roll_path(@guild, @loot_roll), notice: t('controllers.loot_rolls.created_discord_failed', error: e.message)
      end
    else
      @discord_setting = discord_setting
      @channels = fetch_discord_channels if @discord_setting&.connected?
      @synced_roles = @guild.discord_role_syncs.order(:role_name)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    preserve_session
    authorize @loot_roll, :show?
    @entries = @loot_roll.loot_roll_entries.active.ordered_by_roll
    @winner = @loot_roll.winner_entry
  end

  def close
    preserve_session

    if @loot_roll.closed?
      redirect_to guild_loot_roll_path(@guild, @loot_roll), alert: t('controllers.loot_rolls.already_closed')
      return
    end

    @loot_roll.close_and_determine_winner!
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "loot_roll_closed", description: "Closed loot roll \"#{@loot_roll.title}\"", subject: @loot_roll, title: @loot_roll.title)

    # Update Discord message
    begin
      DiscordLootRollService.new(@loot_roll).update_loot_roll_message
    rescue => e
      Rails.logger.error "Failed to update Discord loot roll message: #{e.message}"
    end

    # Broadcast via ActionCable
    broadcast_loot_roll_update

    redirect_to guild_loot_roll_path(@guild, @loot_roll), notice: t('controllers.loot_rolls.closed')
  end

  def force_reroll
    preserve_session

    entry_id = params[:entry_id]
    entry = @loot_roll.loot_roll_entries.find_by(id: entry_id)

    unless entry
      redirect_to guild_loot_roll_path(@guild, @loot_roll), alert: t('controllers.loot_rolls.entry_not_found')
      return
    end

    # Mark the entry as a reroll (allows the user to roll again)
    entry.update!(is_reroll: true)

    # Recalculate winner if closed
    if @loot_roll.closed?
      new_winner = @loot_roll.determine_winner
      @loot_roll.update!(winner_entry: new_winner)
    end

    # Update Discord message
    begin
      DiscordLootRollService.new(@loot_roll).update_loot_roll_message
    rescue => e
      Rails.logger.error "Failed to update Discord loot roll message: #{e.message}"
    end

    # Broadcast via ActionCable
    broadcast_loot_roll_update
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "loot_roll_rerolled", description: "Force reroll on \"#{@loot_roll.title}\"", subject: @loot_roll, title: @loot_roll.title)

    redirect_to guild_loot_roll_path(@guild, @loot_roll), notice: t('controllers.loot_rolls.entry_invalidated')
  end

  def destroy
    preserve_session

    loot_roll_title = @loot_roll.title

    # Delete Discord message if posted
    if @loot_roll.discord_message_id.present? && @loot_roll.discord_channel_id.present?
      begin
        discord_setting = @guild.guild_discord_setting
        bot_token = discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
        RestClient.delete(
          "#{DiscordLootRollService::DISCORD_API_BASE}/channels/#{@loot_roll.discord_channel_id}/messages/#{@loot_roll.discord_message_id}",
          { "Authorization" => "Bot #{bot_token}" }
        )
      rescue => e
        Rails.logger.warn "Failed to delete Discord message: #{e.message}"
      end
    end

    if @loot_roll.soft_delete!
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "loot_roll_deleted", description: "Deleted loot roll \"#{loot_roll_title}\"", title: loot_roll_title)
      session.save if session.respond_to?(:save)
      redirect_to guild_loot_rolls_path(@guild), notice: t('controllers.loot_rolls.deleted', title: loot_roll_title)
    else
      session.save if session.respond_to?(:save)
      redirect_to guild_loot_roll_path(@guild, @loot_roll), alert: t('controllers.loot_rolls.delete_failed')
    end
  end

  private

  def set_guild
    guild_id = params[:guild_id]
    @guild = current_user.guilds.find_by(id: guild_id) ||
             current_user.owned_guilds.find_by(id: guild_id) ||
             Guild.find_by(id: guild_id, owner_id: current_user.id)

    unless @guild
      session.save if session.respond_to?(:save)
      redirect_to my_guilds_path, alert: t('controllers.loot_rolls.access_denied')
    end
  end

  def ensure_guild_member
    return unless @guild

    unless @guild.members.include?(current_user) || @guild.owner == current_user
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.loot_rolls.not_member')
    end
  end

  def set_loot_roll
    @loot_roll = @guild.loot_rolls.find(params[:id])
  end

  def authorize_create
    return unless @guild

    unless can_manage_loot_rolls?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_loot_rolls_path(@guild), alert: t('controllers.loot_rolls.create_denied')
    end
  end

  def authorize_manage
    return unless @loot_roll

    unless @loot_roll.creator == current_user || can_manage_loot_rolls?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_loot_roll_path(@guild, @loot_roll), alert: t('controllers.loot_rolls.manage_denied')
    end
  end

  def loot_roll_params
    permitted = params.require(:loot_roll).permit(:title, :description, :min_roll, :max_roll, :deadline_at)
    sanitize_permitted_text_fields!(permitted, [:title, :description])
  end

  def fetch_discord_channels
    return [] unless @guild.guild_discord_setting&.connected?

    begin
      discord_setting = @guild.guild_discord_setting
      bot_token = discord_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
      discord_service = DiscordService.new(bot_token: bot_token)
      channels = discord_service.get_guild_channels(discord_setting.discord_guild_id)
      channels.select { |c| [0, 15].include?(c["type"]) }
    rescue => e
      Rails.logger.error "Failed to fetch Discord channels: #{e.message}"
      []
    end
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  def broadcast_loot_roll_update
    LootRollsChannel.broadcast_update(@loot_roll)
  end
end
