module Api
  module V1
    class UsersController < BaseController
      before_action :set_user, only: [ :show, :update, :guilds, :archive ]

      def show
        authorize @user
        # Use private view if user is viewing their own profile, extended otherwise
        view = @user == current_user ? :private : :extended
        render json: UserBlueprint.render(@user, view: view)
      end

      def update
        authorize @user
        if @user.update(user_params)
          log_security_event(
            event: "api.user.update",
            status: "success",
            actor: current_user,
            subject: @user
          )
          render json: UserBlueprint.render(@user, view: :private)
        else
          log_security_event(
            event: "api.user.update",
            status: "failure",
            actor: current_user,
            subject: @user,
            metadata: { error_count: @user.errors.count }
          )
          render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def guilds
        authorize @user, :guilds?
        guild_scope = @user.guilds.includes(:owner, :guild_members).order(created_at: :desc, id: :desc)
        @guilds, pagination = paginate_relation(guild_scope)
        render json: {
          guilds: GuildBlueprint.render_as_hash(@guilds),
          pagination: pagination
        }
      end

      def archive
        authorize @user, :archive?

        if @user.update(archived: true)
          log_security_event(
            event: "api.user.archive",
            status: "success",
            actor: current_user,
            subject: @user
          )
          render json: { message: t("api.users.account_archived") }, status: :ok
        else
          log_security_event(
            event: "api.user.archive",
            status: "failure",
            actor: current_user,
            subject: @user,
            metadata: { error_count: @user.errors.count }
          )
          render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_user
        @user = User.includes(current_subscription: :pricing_plan).find_by(id: params[:id])
        policy = @user && UserPolicy.new(current_user, @user)

        allowed = case action_name
                  when "show"
                    policy&.show?
                  when "update"
                    policy&.update?
                  when "guilds"
                    policy&.guilds?
                  when "archive"
                    policy&.archive?
                  else
                    false
                  end

        return if allowed

        return render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      end

      def user_params
        # SECURITY: Do not allow email changes via API
        # Email changes should require re-authentication and confirmation
        params.require(:user).permit(:username)
      end
    end
  end
end
