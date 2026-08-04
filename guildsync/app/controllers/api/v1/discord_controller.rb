module Api
  module V1
    class DiscordController < BaseController
      before_action :set_guild_for_discord_channel_management, only: [ :channels, :update_channels ]
      before_action :set_guild_for_discord_event_signup, only: [ :signup_event ]

      def channels
        discord_setting = @guild.guild_discord_setting

        unless discord_setting&.connected?
          render json: { error: t("api.discord.not_connected") }, status: :unprocessable_entity
          return
        end

        begin
          discord_service = DiscordService.new(bot_token: discord_setting.bot_token)
          channels = discord_service.get_guild_channels(discord_setting.discord_guild_id)

          # Filter to text channels only
          text_channels = channels.select { |c| c["type"] == 0 } # GUILD_TEXT
          sorted_channels = text_channels.sort_by { |channel| [ channel["position"].to_i, channel["id"].to_s ] }
          paginated_channels, pagination = paginate_array(sorted_channels)

          render json: {
            channels: paginated_channels,
            pagination: pagination
          }
        rescue => e
          Rails.logger.error "Failed to fetch Discord channels: #{e.message}"
          render json: { error: t("api.discord.fetch_channels_failed", message: e.message) }, status: :internal_server_error
        end
      end

      def update_channels
        discord_setting = @guild.guild_discord_setting

        unless discord_setting&.connected?
          render json: { error: t("api.discord.not_connected") }, status: :unprocessable_entity
          return
        end

        if discord_setting.update(channel_params)
          render json: {
            message: t("api.discord.channels_updated"),
            settings: {
              events_channel_id: discord_setting.events_channel_id,
              gear_channel_id: discord_setting.gear_channel_id,
              polls_channel_id: discord_setting.polls_channel_id
            }
          }
        else
          render json: { errors: discord_setting.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def signup_event
        event = @guild.events.find_by(id: params[:event_id])

        unless event
          render json: { error: t("api.discord.event_not_found") }, status: :not_found
          return
        end

        discord_user_id = params[:discord_user_id]
        discord_username = params[:discord_username]

        unless discord_user_id && discord_username
          render json: { error: t("api.discord.missing_discord_identity") }, status: :unprocessable_entity
          return
        end

        begin
          participation = event.discord_event_participations.find_or_create_by!(
            discord_user_id: discord_user_id
          ) do |p|
            p.discord_username = discord_username
            p.discord_message_id = params[:discord_message_id]
          end

          # Update event message with new participant count
          DiscordUpdateEventParticipantsJob.perform_later(event.id)

          render json: {
            message: t("api.discord.signup_success"),
            participation: {
              discord_user_id: participation.discord_user_id,
              discord_username: participation.discord_username
            }
          }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error "Failed to sign up for event: #{e.message}"
          render json: { error: t("api.discord.signup_failed", message: e.message) }, status: :internal_server_error
        end
      end

      private

      def set_guild_for_discord_channel_management
        @guild = resolve_guild_for_discord_api(params[:guild_id])
        unless @guild
          render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
          return
        end
        authorize @guild, :manage_discord?
      end

      def set_guild_for_discord_event_signup
        @guild = resolve_guild_for_discord_api(params[:guild_id])
        unless @guild
          render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
          return
        end
        authorize @guild, :signup_discord_event_participation?
      end

      def resolve_guild_for_discord_api(guild_id)
        g = current_user.guilds.find_by(id: guild_id)
        g ||= current_user.owned_guilds.find_by(id: guild_id)
        g ||= Guild.find_by(id: guild_id, owner_id: current_user.id)
        g
      end

      def channel_params
        params.require(:channels).permit(:events_channel_id, :gear_channel_id, :polls_channel_id)
      end
    end
  end
end
