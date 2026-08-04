class PollsController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :ensure_guild_member
  before_action :set_poll, only: [:show, :vote, :post_to_discord, :destroy]
  before_action :authorize_create, only: [:new, :create, :post_to_discord]
  before_action :authorize_destroy, only: [:destroy]

  def index
    preserve_session
    authorize @guild, :show?
    @polls = @guild.polls.includes(:creator, :poll_votes).ordered
  end

  def new
    preserve_session
    @poll = @guild.polls.build
    authorize @poll, :new? # Authorize poll creation (policy handles both Poll and Guild)
    @discord_setting = @guild.guild_discord_setting
    @channels = fetch_discord_channels if @discord_setting&.connected?
    @synced_roles = @guild.discord_role_syncs.order(:role_name)
  end

  def create
    preserve_session
    @poll = @guild.polls.build(poll_params)
    @poll.creator = current_user
    @poll.discord_role_mentions = (params[:discord_role_mentions] || []).uniq
    authorize @poll, :create?

    # Use polls_channel_id from guild settings if not specified
    if @poll.discord_channel_id.blank?
      discord_setting = @guild.guild_discord_setting
      @poll.discord_channel_id = discord_setting&.polls_channel_id
    end

    if @poll.save
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "poll_created", description: "Created poll \"#{@poll.title}\"", subject: @poll, title: @poll.title)
      session.save if session.respond_to?(:save)
      
      # Auto-post to Discord if polls channel is configured
      discord_setting = @guild.guild_discord_setting
      if discord_setting&.connected? && discord_setting.polls_channel_id.present?
        begin
          @poll.update_column(:discord_channel_id, discord_setting.polls_channel_id) if @poll.discord_channel_id.blank?
          service = DiscordPollService.new(@poll)
          service.post_poll
          redirect_to guild_poll_path(@guild, @poll), notice: t('controllers.polls.created_discord')
        rescue => e
          Rails.logger.error "Failed to auto-post poll to Discord: #{e.message}"
          redirect_to guild_poll_path(@guild, @poll), notice: t('controllers.polls.created_discord_failed', error: e.message)
        end
      else
        redirect_to guild_poll_path(@guild, @poll), notice: t('controllers.polls.created')
      end
      return
    else
      @discord_setting = @guild.guild_discord_setting
      @channels = fetch_discord_channels if @discord_setting&.connected?
      @synced_roles = @guild.discord_role_syncs.order(:role_name)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    preserve_session
    authorize @poll, :show?
    @current_user_vote = @poll.user_vote(current_user)
    @vote_counts = @poll.vote_counts
    @vote_percentages = @poll.vote_percentages
  end

  def vote
    preserve_session
    authorize @poll, :vote?

    choice = params[:choice]&.to_i

    unless PollVote.choices.values.include?(choice)
      render json: { error: t('controllers.polls.vote.invalid_choice') }, status: :unprocessable_entity
      return
    end

    # Check if poll is still open
    unless @poll.open?
      render json: { error: t('controllers.polls.vote.poll_closed') }, status: :unprocessable_entity
      return
    end

    # Find or create vote
    vote = @poll.poll_votes.find_or_initialize_by(user: current_user)
    vote.choice = choice

    if vote.save
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "poll_voted", description: "Voted on poll \"#{@poll.title}\"", subject: @poll, title: @poll.title)
      # Update Discord message if posted
      if @poll.discord_message_id.present?
        DiscordPollService.new(@poll).update_poll_message
      end

      # Broadcast update via ActionCable
      broadcast_poll_update

      render json: {
        success: true,
        vote_counts: @poll.reload.vote_counts,
        vote_percentages: @poll.vote_percentages,
        user_vote: choice
      }
    else
      render json: { error: vote.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def post_to_discord
    preserve_session
    authorize @poll, :post_to_discord?

    # Ensure poll uses the polls channel from settings
    discord_setting = @guild.guild_discord_setting
    if @poll.discord_channel_id.blank? && discord_setting&.polls_channel_id.present?
      @poll.update_column(:discord_channel_id, discord_setting.polls_channel_id)
    end

    begin
      service = DiscordPollService.new(@poll)
      service.post_poll
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "poll_posted_discord", description: "Posted poll \"#{@poll.title}\" to Discord", subject: @poll, title: @poll.title)
      redirect_to guild_poll_path(@guild, @poll), notice: t('controllers.polls.posted_discord')
    rescue => e
      Rails.logger.error "Failed to post poll to Discord: #{e.message}"
      redirect_to guild_poll_path(@guild, @poll), alert: t('controllers.polls.post_discord_failed', error: e.message)
    end
  end

  def destroy
    preserve_session
    authorize @poll, :destroy?

    poll_title = @poll.title
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "poll_deleted", description: "Deleted poll \"#{poll_title}\"", title: poll_title)
    
    # Delete Discord message if posted
    if @poll.discord_message_id.present? && @poll.discord_channel_id.present?
      begin
        discord_setting = @guild.guild_discord_setting
        bot_token = discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
        RestClient.delete(
          "#{DiscordPollService::DISCORD_API_BASE}/channels/#{@poll.discord_channel_id}/messages/#{@poll.discord_message_id}",
          { "Authorization" => "Bot #{bot_token}" }
        )
      rescue => e
        Rails.logger.warn "Failed to delete Discord message: #{e.message}"
        # Continue with poll deletion even if Discord message deletion fails
      end
    end

    if @poll.soft_delete!
      session.save if session.respond_to?(:save)
      redirect_to guild_polls_path(@guild), notice: t('controllers.polls.deleted', title: poll_title)
    else
      session.save if session.respond_to?(:save)
      redirect_to guild_poll_path(@guild, @poll), alert: t('controllers.polls.delete_failed', errors: @poll.errors.full_messages.join(', '))
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
      redirect_to my_guilds_path, alert: t('controllers.polls.access_denied')
    end
  end

  def ensure_guild_member
    return unless @guild

    unless @guild.members.include?(current_user) || @guild.owner == current_user
      session.save if session.respond_to?(:save)
      redirect_to guild_path(@guild), alert: t('controllers.polls.not_member')
    end
  end

  def set_poll
    @poll = @guild.polls.find(params[:id])
  end

  def authorize_create
    return unless @guild

    unless can_manage_polls?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_polls_path(@guild), alert: t('controllers.polls.create_denied')
    end
  end

  def authorize_destroy
    return unless @poll

    unless @poll.creator == current_user || can_manage_polls?(@guild)
      session.save if session.respond_to?(:save)
      redirect_to guild_poll_path(@guild, @poll), alert: t('controllers.polls.delete_denied')
    end
  end

  def poll_params
    permitted = params.require(:poll).permit(:title, :description, :deadline, :anonymous)
    sanitize_permitted_text_fields!(permitted, [:title, :description])
  end

  def fetch_discord_channels
    return [] unless @guild.guild_discord_setting&.connected?

    begin
      discord_setting = @guild.guild_discord_setting
      bot_token = discord_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
      discord_service = DiscordService.new(bot_token: bot_token)
      channels = discord_service.get_guild_channels(discord_setting.discord_guild_id)
      # Only show text channels (type 0) and forum channels (type 15)
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

  def broadcast_poll_update
    # Broadcast to ActionCable channel
    PollsChannel.broadcast_to(@poll, {
      type: 'vote_update',
      vote_counts: @poll.reload.vote_counts,
      vote_percentages: @poll.vote_percentages,
      total_votes: @poll.total_votes
    })
  end
end
