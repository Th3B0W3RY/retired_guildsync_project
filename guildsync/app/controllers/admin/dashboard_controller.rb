# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    DASHBOARD_INDEX_MAIN_FRAME = "admin_dashboard_index_main"

    def index
      load_dashboard_index
      return render("dashboard_index_frame", layout: false) if request.headers["Turbo-Frame"] == DASHBOARD_INDEX_MAIN_FRAME
    end

    private

    def load_dashboard_index
      @stats = {
        total_users: User.count,
        total_guilds: Guild.count,
        total_events: Event.count,
        total_games: Game.count,
        total_alliances: Alliance.count,
        pending_games: Game.pending.count,
        moderation_pending: FeatureRequest.pending_review.count + FeatureRequestComment.pending_review.count,
        paying_subscribers_count: Admin::SubscriptionDirectory.paying_users_relation.count,
        trials_and_free_count: Admin::SubscriptionDirectory.trials_and_free_users_relation.count
      }
    end
  end
end
