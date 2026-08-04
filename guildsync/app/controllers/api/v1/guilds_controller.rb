module Api
  module V1
    class GuildsController < BaseController
      before_action :set_guild, only: [ :show, :update, :destroy ]

      def index
        guild_scope = current_user.guilds.order(created_at: :desc, id: :desc)
        @guilds, pagination = paginate_relation(guild_scope)
        render json: {
          guilds: GuildBlueprint.render_as_hash(@guilds),
          pagination: pagination
        }
      end

      def show
        authorize @guild
        render json: { guild: GuildBlueprint.render_as_hash(@guild, view: :extended) }
      end

      def create
        @guild = Guild.new(guild_params)
        @guild.owner = current_user
        authorize @guild

        if @guild.save
          # Add owner as a member
          owner_member = @guild.guild_members.create(user: current_user, role: :owner, status: :active)
          unless owner_member.persisted?
            @guild.destroy
            render json: { errors: owner_member.errors.full_messages }, status: :unprocessable_entity
            return
          end
          log_security_event(
            event: "api.guild.create",
            status: "success",
            actor: current_user,
            subject: @guild
          )
          render json: { guild: GuildBlueprint.render_as_hash(@guild, view: :extended) }, status: :created
        else
          log_security_event(
            event: "api.guild.create",
            status: "failure",
            actor: current_user,
            metadata: { error_count: @guild.errors.count }
          )
          render json: { errors: @guild.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        authorize @guild
        if @guild.update(guild_params)
          log_security_event(
            event: "api.guild.update",
            status: "success",
            actor: current_user,
            subject: @guild
          )
          render json: { guild: GuildBlueprint.render_as_hash(@guild) }
        else
          log_security_event(
            event: "api.guild.update",
            status: "failure",
            actor: current_user,
            subject: @guild,
            metadata: { error_count: @guild.errors.count }
          )
          render json: { errors: @guild.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @guild
        log_security_event(
          event: "api.guild.destroy",
          status: "success",
          actor: current_user,
          subject: @guild
        )
        @guild.destroy
        head :no_content
      end

      private

      def set_guild
        gid = params[:id]
        @guild = current_user.guilds.find_by(id: gid)
        @guild ||= current_user.owned_guilds.find_by(id: gid)
        @guild ||= Guild.find_by(id: gid, owner_id: current_user.id)
        @guild ||= Guild.find_by(id: gid, publicly_listed: true) if action_name == "show"

        return if @guild

        render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      end

      def guild_params
        permitted = params.require(:guild).permit(:name, :description, :avatar_url, settings: {})
        sanitize_permitted_text_fields!(permitted, [ :name, :description, :avatar_url ])
      end
    end
  end
end
