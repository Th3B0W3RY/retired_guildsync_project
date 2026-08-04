# frozen_string_literal: true

module Api
  module V1
    class GuildInvitesController < BaseController
      before_action :set_guild, only: [ :index, :create, :destroy ]
      before_action :set_invite_for_guild, only: [ :destroy ]
      before_action :set_invite_for_user, only: [ :accept, :deny ]

      def index
        authorize GuildInvite.new(guild: @guild, invited_by: current_user)
        scope = @guild.guild_invites.includes(:user, :invited_by).order(created_at: :desc)
        invites, pagination = paginate_relation(scope)
        render json: {
          invites: GuildInviteBlueprint.render_as_hash(invites),
          pagination: pagination
        }
      end

      def create
        @invite = @guild.guild_invites.build(invite_params)
        @invite.invited_by = current_user
        @invite.status = :pending
        authorize @invite

        if @invite.save
          render json: GuildInviteBlueprint.render(@invite), status: :created
        else
          render json: { errors: @invite.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @invite
        @invite.destroy
        head :no_content
      end

      def accept
        authorize @invite
        unless @invite.pending?
          return render json: { error: t("api.v1.guild_invites.not_pending") }, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          guild = @invite.guild
          unless guild.guild_members.exists?(user_id: current_user.id)
            guild.guild_members.create!(
              user: current_user,
              role: :member,
              status: :active,
              discord_role_id: guild.default_role_id
            )
          end
          @invite.update!(status: :accepted)
        end

        render json: GuildInviteBlueprint.render(@invite)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      def deny
        authorize @invite
        unless @invite.pending?
          return render json: { error: t("api.v1.guild_invites.not_pending") }, status: :unprocessable_entity
        end

        @invite.update!(status: :denied)
        render json: GuildInviteBlueprint.render(@invite)
      end

      private

      def set_guild
        @guild = Guild.find_by(id: params[:guild_id])
        return if @guild

        render json: { error: t("api.v1.resource_not_found") }, status: :not_found
      end

      def set_invite_for_guild
        @invite = @guild.guild_invites.find_by(id: params[:id])
        return if @invite

        render json: { error: t("api.v1.resource_not_found") }, status: :not_found
      end

      def set_invite_for_user
        @invite = GuildInvite.find_by(id: params[:id], user_id: current_user.id)
        return if @invite

        render json: { error: t("api.v1.resource_not_found") }, status: :not_found
      end

      def invite_params
        params.require(:invite).permit(:user_id)
      end
    end
  end
end
