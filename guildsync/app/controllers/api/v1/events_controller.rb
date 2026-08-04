module Api
  module V1
    class EventsController < BaseController
      before_action :set_guild_for_guild_events, only: [ :index, :create ]
      before_action :set_event, only: [ :show, :update, :destroy, :participate, :unparticipate, :participants ]

      def index
        event_scope = Event.where(guild_id: @guild.id).order(scheduled_at: :desc, id: :desc)

        @events, pagination = paginate_relation(event_scope)
        render json: {
          events: EventBlueprint.render_as_hash(@events),
          pagination: pagination
        }
      end

      def show
        authorize @event
        render json: EventBlueprint.render(@event, view: :extended)
      end

      def create
        @event = Event.new(event_params)
        @event.guild = @guild
        @event.created_by = current_user
        authorize @event

        if @event.save
          # Post to Discord if guild has Discord connected
          if @event.guild.guild_discord_setting&.connected? && @event.guild.guild_discord_setting.events_channel_configured?
            DiscordPostEventJob.perform_later(@event.id)
          end

          log_security_event(
            event: "api.event.create",
            status: "success",
            actor: current_user,
            subject: @event
          )
          render json: EventBlueprint.render(@event), status: :created
        else
          log_security_event(
            event: "api.event.create",
            status: "failure",
            actor: current_user,
            metadata: { error_count: @event.errors.count }
          )
          render json: { errors: @event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        authorize @event
        if @event.update(event_params)
          log_security_event(
            event: "api.event.update",
            status: "success",
            actor: current_user,
            subject: @event
          )
          render json: EventBlueprint.render(@event)
        else
          log_security_event(
            event: "api.event.update",
            status: "failure",
            actor: current_user,
            subject: @event,
            metadata: { error_count: @event.errors.count }
          )
          render json: { errors: @event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @event
        log_security_event(
          event: "api.event.destroy",
          status: "success",
          actor: current_user,
          subject: @event
        )
        @event.soft_delete!
        head :no_content
      end

      def participate
        authorize @event
        participation = @event.event_participations.find_or_initialize_by(user: current_user)
        participation.status = params[:status] || :attending
        participation.notes = params[:notes] if params[:notes]

        if participation.save
          render json: EventParticipationBlueprint.render(participation)
        else
          render json: { errors: participation.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def unparticipate
        authorize @event, :participate?
        participation = @event.event_participations.find_by(user: current_user)

        if participation.nil?
          return render json: { error: t("api.v1.not_participating") }, status: :not_found
        end

        participation.destroy
        head :no_content
      end

      def participants
        authorize @event
        participants_scope = @event.event_participations.includes(:user).order(created_at: :desc, id: :desc)
        participants, pagination = paginate_relation(participants_scope)
        render json: {
          participants: EventParticipationBlueprint.render_as_hash(participants),
          pagination: pagination
        }
      end

      private

      def set_guild_for_guild_events
        gid = params[:guild_id]

        if gid.blank?
          render json: { error: t("api.v1.guild_id_required") }, status: :bad_request
          return
        end

        @guild = current_user.guilds.find_by(id: gid)
        @guild ||= current_user.owned_guilds.find_by(id: gid)
        @guild ||= Guild.find_by(id: gid, owner_id: current_user.id)

        return if @guild

        render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      end

      def set_event
        @event = Event.find_by(id: params[:id])
        return if @event && EventPolicy.new(current_user, @event).show?

        return render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      end

      def event_params
        permitted = params.require(:event).permit(:title, :description, :event_type, :scheduled_at, :duration, :status, :squad_leader, :location)
        sanitize_permitted_text_fields!(permitted, [ :title, :description, :squad_leader, :location ])
      end
    end
  end
end
