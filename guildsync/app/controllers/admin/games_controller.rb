# frozen_string_literal: true

module Admin
  class GamesController < BaseController
    GAMES_INDEX_RESULTS_FRAME = "admin_games_index_results"
    GAMES_PENDING_MAIN_FRAME = "admin_games_pending_main"

    def index
      load_games_index
      if request.headers["Turbo-Frame"] == GAMES_INDEX_RESULTS_FRAME
        render "games_index_results_frame", layout: false
      end
    end

    def search
      query = sanitize_search_input(params[:q])
      
      if query.blank? || query.length < 1
        render json: { games: [] }
        return
      end
      
      games = Game.active.where("name ILIKE ?", "%#{query}%")
                  .order(:name)
                  .limit(10)
      
      render json: {
        games: games.map { |g| 
          {
            id: g.id,
            name: g.name,
            description: g.description&.truncate(100)
          }
        }
      }
    end
    
    def pending
      @pending_games = Game.pending.order(created_at: :desc)
      if request.headers["Turbo-Frame"] == GAMES_PENDING_MAIN_FRAME
        render "games_pending_main_frame", layout: false
      end
    end
    
    def approve
      @game = Game.find(params[:id])
      removed_id = @game.id
      changes = @game.changes

      if @game.update(active: true, deactivated_at: nil, deactivated_by_id: nil, deactivation_reason: nil)
        log_admin_action(action: "approve_game", record: @game, changes_data: changes)
        assign_pending_turbo_state(
          removed_id: removed_id,
          notice: I18n.t("admin.games.flash.approved", name: @game.name)
        )
        respond_to_pending_action
      else
        respond_to_pending_failure(
          I18n.t("admin.games.flash.approve_failed", errors: @game.errors.full_messages.join(", "))
        )
      end
    end

    def deny
      @game = Game.find(params[:id])
      removed_id = @game.id
      changes = @game.changes

      # Mark as denied by setting deactivated_at without ever activating
      if @game.update(deactivated_at: Time.current, deactivation_reason: "Denied by admin")
        log_admin_action(action: "deny_game", record: @game, changes_data: changes)
        assign_pending_turbo_state(
          removed_id: removed_id,
          notice: I18n.t("admin.games.flash.denied", name: @game.name)
        )
        respond_to_pending_action
      else
        respond_to_pending_failure(
          I18n.t("admin.games.flash.deny_failed", errors: @game.errors.full_messages.join(", "))
        )
      end
    end

    def reject
      @game = Game.find(params[:id])
      removed_id = @game.id
      game_name = @game.name

      if @game.destroy
        log_admin_action(action: "reject_game", record: @game, changes_data: { name: game_name })
        assign_pending_turbo_state(
          removed_id: removed_id,
          notice: I18n.t("admin.games.flash.rejected", name: game_name)
        )
        respond_to_pending_action
      else
        respond_to_pending_failure(
          I18n.t("admin.games.flash.reject_failed", errors: @game.errors.full_messages.join(", "))
        )
      end
    end
    
    def destroy
      @game = Game.find(params[:id])
      game_name = @game.name
      
      if @game.destroy
        log_admin_action(action: "destroy_game", record: @game, changes_data: { name: game_name })
        redirect_to admin_games_path, notice: I18n.t("admin.games.flash.deleted_from_cache", name: game_name)
      else
        redirect_to admin_games_path, alert: I18n.t("admin.games.flash.delete_failed", errors: @game.errors.full_messages.join(", "))
      end
    end

    private

    def load_games_index
      @active_games = Game.active.order(:name)
      @query = sanitize_search_input(params[:q])

      if @query.present?
        @active_games = @active_games.where("name ILIKE ?", "%#{@query}%")
      end
    end

    def assign_pending_turbo_state(removed_id:, notice:)
      @removed_pending_game_id = removed_id
      @pending_games = Game.pending.order(created_at: :desc)
      @admin_games_notice = notice
    end

    def respond_to_pending_action
      respond_to do |format|
        format.html { redirect_to pending_games_admin_games_path, notice: @admin_games_notice }
        format.turbo_stream { render :pending_list_update }
      end
    end

    def respond_to_pending_failure(alert_message)
      respond_to do |format|
        format.html { redirect_to pending_games_admin_games_path, alert: alert_message }
        format.turbo_stream do
          @admin_games_alert = alert_message
          render :pending_action_alert
        end
      end
    end
  end
end


