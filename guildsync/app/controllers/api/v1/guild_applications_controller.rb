# frozen_string_literal: true

module Api
  module V1
    class GuildApplicationsController < BaseController
      before_action :set_guild
      before_action :set_application, only: [ :show, :update ]

      def index
        authorize GuildApplication.new(guild: @guild)
        scope = @guild.guild_applications.includes(:user).order(created_at: :desc)
        applications, pagination = paginate_relation(scope)
        render json: {
          applications: GuildApplicationBlueprint.render_as_hash(applications),
          pagination: pagination
        }
      end

      def show
        authorize @application
        render json: GuildApplicationBlueprint.render(@application)
      end

      def create
        @application = @guild.guild_applications.build(application_params)
        @application.user = current_user
        @application.status = :pending
        authorize @application

        if @application.save
          log_security_event(
            event: "api.guild_application.create",
            status: "success",
            actor: current_user,
            subject: @application,
            metadata: { guild_id: @guild.id }
          )
          render json: GuildApplicationBlueprint.render(@application), status: :created
        else
          render json: { errors: @application.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        authorize @application
        new_status = params.dig(:application, :status) || params[:status]

        case new_status
        when "accepted"
          process_accept
        when "rejected"
          process_reject
        else
          render json: { error: t("api.v1.guild_applications.invalid_status") }, status: :unprocessable_entity
        end
      end

      private

      def process_accept
        unless @application.pending?
          return render json: { error: t("api.v1.guild_applications.not_pending") }, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          guild = @application.guild
          guild_member = guild.guild_members.find_by(user_id: @application.user_id)
          if guild_member
            guild_member.update!(status: :active)
          else
            guild.guild_members.create!(
              user_id: @application.user_id,
              role: :member,
              status: :active,
              discord_role_id: guild.default_role_id
            )
          end
          @application.accepted!
        end

        log_security_event(
          event: "api.guild_application.accepted",
          status: "success",
          actor: current_user,
          subject: @application,
          metadata: { guild_id: @application.guild_id }
        )
        render json: GuildApplicationBlueprint.render(@application)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      def process_reject
        unless @application.pending?
          return render json: { error: t("api.v1.guild_applications.not_pending") }, status: :unprocessable_entity
        end

        @application.rejected!
        log_security_event(
          event: "api.guild_application.rejected",
          status: "success",
          actor: current_user,
          subject: @application,
          metadata: { guild_id: @application.guild_id }
        )
        render json: GuildApplicationBlueprint.render(@application)
      end

      def set_guild
        @guild = Guild.find_by(id: params[:guild_id])
        return if @guild

        render json: { error: t("api.v1.resource_not_found") }, status: :not_found
      end

      def set_application
        @application = @guild.guild_applications.find_by(id: params[:id])
        return if @application

        render json: { error: t("api.v1.resource_not_found") }, status: :not_found
      end

      def application_params
        permitted = params.require(:application).permit(:discord_username, :message, :character_details)
        sanitize_permitted_text_fields!(permitted, [ :discord_username, :message, :character_details ])
      end
    end
  end
end
