class HomeController < ApplicationController
  layout "application"

  skip_before_action :authenticate_user!, only: [ :landing, :pricing ]
  skip_before_action :require_mfa_if_enabled, only: [ :landing, :pricing ]

  def landing
    # Redirect logged-in users to the appropriate authenticated page
    if user_signed_in? && current_user.present?
      if mfa_verified_for_session?
        redirect_to dashboard_path
        return
      else
        # User has a valid session but isn't fully authenticated yet (e.g. just signed up or logged in).
        # Do NOT clear the session here – send them into the normal post-login flow so MFA/profile
        # completion can run instead of silently logging them out.
        redirect_to after_sign_in_path_for(current_user)
        return
      end
    end

    # Public marketing landing page - accessible to everyone
    # Always clear any alert messages on the landing page to prevent stale messages
    flash.delete(:alert) if flash[:alert].present?

    @landing_compare_section_title = LandingCompare::Repository.section_title
    @landing_compare_tables = LandingCompare::Repository.tables_for_public
    @landing_user_feedbacks = LandingUserFeedback.visible.with_rich_text_body.ordered.limit(LandingUserFeedback::MAX_ENTRIES).to_a
    @homepage_feature_cards = HomepageFeatureCard.visible.ordered.to_a
  end

  def pricing
    # Public pricing page - accessible to everyone
  end

  def dashboard
    preserve_session
    # Do not reset_session here — signed-in users pending MFA must be sent to the step-up flow,
    # not logged out (and never render dashboard data before session MFA is satisfied).
    unless user_signed_in? && current_user.present?
      redirect_to login_path, alert: I18n.t("dashboard.sign_in_required")
      return
    end

    unless mfa_verified_for_session?
      redirect_to mfa_verification_path(return_to: dashboard_path),
                  alert: I18n.t("controllers.application.mfa.verify_identity")
      return
    end

    load_dashboard_data
  end

  def dashboard_stats
    preserve_session
    unless user_signed_in? && current_user.present? && mfa_verified_for_session?
      head :unauthorized
      return
    end

    load_dashboard_data
    render partial: "home/dashboard_stats"
  end

  def recent_activity
    unless user_signed_in? && current_user.present? && mfa_verified_for_session?
      head :unauthorized
      return
    end

    activities = current_user.user_recent_activities.recent_first.limit(10)
    render partial: "home/recent_activity_list", locals: { activities: activities }, layout: false
  end

  def activity
    preserve_session
    unless user_signed_in? && current_user.present?
      redirect_to login_path, alert: I18n.t("dashboard.sign_in_required")
      return
    end

    unless mfa_verified_for_session?
      redirect_to mfa_verification_path(return_to: dashboard_activity_path),
                  alert: I18n.t("controllers.application.mfa.verify_identity")
      return
    end

    @activities = current_user.user_recent_activities.recent_first.limit(UserRecentActivity::MAX_RECENT)
  end

  private

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end

  def load_dashboard_data
    @guilds = dashboard_context_guilds
    @invitable_guilds = @guilds.select { |guild| can_manage_applications?(guild) }
    @event_manage_guilds = @guilds.select { |guild| can_manage_events?(guild) }
    @poll_manage_guilds = @guilds.select { |guild| can_manage_polls?(guild) }
    @loot_manage_guilds = @guilds.select { |guild| can_manage_loot_rolls?(guild) }
    @warning_manage_guilds = @guilds.select { |guild| can_manage_warnings?(guild) }

    guild_ids = @guilds.map(&:id)
    managed_guild_ids = @invitable_guilds.map(&:id)
    warning_guild_ids = @warning_manage_guilds.map(&:id)

    @pending_items = {
      applications: managed_guild_ids.any? ? GuildApplication.where(guild_id: managed_guild_ids, status: :pending).count : 0,
      invites: GuildInvite.where(user_id: current_user.id, status: :pending, dismissed: false).count,
      warnings: warning_guild_ids.any? ? GuildMemberWarningStatus.where(guild_id: warning_guild_ids, state: [ :warned, :banned ]).count : 0
    }

    # Member-visible aggregates only (active guild memberships), not officer/owner health metrics.
    @member_activity =
      if guild_ids.any?
        upcoming = DiscordEvent.where(guild_id: guild_ids).where("scheduled_at >= ?", Time.current)
        {
          upcoming_events_count: upcoming.count,
          upcoming_events_preview: upcoming.order(:scheduled_at).limit(3).to_a,
          open_polls_count: Poll.open.where(guild_id: guild_ids).count,
          open_loot_rolls_count: LootRoll.open_for_participation.where(guild_id: guild_ids).count
        }
      else
        {
          upcoming_events_count: 0,
          upcoming_events_preview: [],
          open_polls_count: 0,
          open_loot_rolls_count: 0
        }
      end
  end

  # Guilds the user should see on the global dashboard: active membership in a non-archived guild,
  # or ownership of a non-archived guild (covers edge cases where owner row is missing).
  def dashboard_context_guilds
    member_guild_ids = current_user.guild_members
      .active
      .joins(:guild)
      .merge(Guild.not_archived)
      .distinct
      .pluck(:guild_id)
    owned_ids = current_user.owned_guilds.not_archived.pluck(:id)
    ids = (member_guild_ids + owned_ids).uniq
    Guild.where(id: ids).includes(:guild_members).order(:name)
  end
end
