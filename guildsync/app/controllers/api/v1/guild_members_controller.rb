module Api
  module V1
    class GuildMembersController < BaseController
      before_action :set_guild
      before_action :set_guild_member, only: [ :show, :update, :destroy ]
      before_action :authorize_guild_access

      def index
        members_scope = @guild.guild_members.includes(:user).order(created_at: :desc, id: :desc)
        @members, pagination = paginate_relation(members_scope)
        render json: {
          members: GuildMemberBlueprint.render_as_hash(@members),
          pagination: pagination
        }
      end

      def show
        render json: GuildMemberBlueprint.render(@guild_member)
      end

      def create
        @guild_member = @guild.guild_members.build(guild_member_attributes)
        @guild_member.user_id = params[:user_id] || current_user.id
        authorize @guild_member

        if @guild_member.save
          log_security_event(
            event: "api.guild_member.create",
            status: "success",
            actor: current_user,
            subject: @guild_member,
            metadata: { guild_id: @guild.id }
          )
          render json: GuildMemberBlueprint.render(@guild_member), status: :created
        else
          log_security_event(
            event: "api.guild_member.create",
            status: "failure",
            actor: current_user,
            metadata: { guild_id: @guild.id, error_count: @guild_member.errors.count }
          )
          render json: { errors: @guild_member.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        authorize @guild_member
        if @guild_member.update(guild_member_attributes)
          log_security_event(
            event: "api.guild_member.update",
            status: "success",
            actor: current_user,
            subject: @guild_member,
            metadata: { guild_id: @guild.id }
          )
          render json: GuildMemberBlueprint.render(@guild_member)
        else
          log_security_event(
            event: "api.guild_member.update",
            status: "failure",
            actor: current_user,
            subject: @guild_member,
            metadata: { guild_id: @guild.id, error_count: @guild_member.errors.count }
          )
          render json: { errors: @guild_member.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @guild_member
        log_security_event(
          event: "api.guild_member.destroy",
          status: "success",
          actor: current_user,
          subject: @guild_member,
          metadata: { guild_id: @guild.id }
        )
        @guild_member.destroy
        head :no_content
      end

      private

      def set_guild
        gid = params[:guild_id]
        @guild = current_user.guilds.find_by(id: gid)
        @guild ||= current_user.owned_guilds.find_by(id: gid)
        @guild ||= Guild.find_by(id: gid, owner_id: current_user.id)

        return if @guild

        render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      end

      def set_guild_member
        @guild_member = @guild.guild_members.find_by(id: params[:id])
        return if @guild_member

        render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      end

      def authorize_guild_access
        return if @guild.guild_members.exists?(user_id: current_user.id) || @guild.owner == current_user

        render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      end

      def guild_member_attributes
        GuildMember::ApiAttributes.extract(
          params.require(:guild_member),
          guild: @guild,
          acting_user: current_user
        )
      end
    end
  end
end
