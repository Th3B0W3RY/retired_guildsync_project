# frozen_string_literal: true

module UserActivity
  # Decides how a tracked page view should appear in the user's Recent Activity feed:
  # whether to record it at all, the user-facing label, and whether it links anywhere.
  #
  # Internal/technical endpoints (OAuth verify round-trips, dashboard polling, the feed
  # itself) are never recorded. Authentication callbacks are recorded as a plain
  # "Signed in" entry with no link. Everything else is a normal page the user can revisit.
  class Descriptor
    Result = Struct.new(:skip, :label, :link_path, keyword_init: true) do
      def skip?
        skip
      end

      def linkable?
        link_path.present?
      end
    end

    # Actions that must never surface in the feed (polling, OAuth round-trips, the feed page).
    SKIP_ACTIONS = {
      "home" => %w[dashboard recent_activity dashboard_stats activity].freeze,
      "sessions" => %w[new create destroy].freeze,
      "discord_user_auth" => %w[start success verify_session].freeze,
      "google_user_auth" => %w[start success verify_session].freeze,
      "microsoft_user_auth" => %w[start success verify_session].freeze
    }.freeze

    # OAuth callbacks recorded as a friendly "signed in" entry, never as a clickable link.
    SIGN_IN_CONTROLLERS = %w[discord_user_auth google_user_auth microsoft_user_auth].freeze

    # Paths whose pages must never be linkable even when recorded (auth/session surfaces).
    NON_LINKABLE_PREFIXES = %w[/auth /login /sign_in /sign_out /logout].freeze

    def self.build(controller_name:, action_name:, path:, label_override: nil)
      new(
        controller_name: controller_name,
        action_name: action_name,
        path: path,
        label_override: label_override
      ).result
    end

    def initialize(controller_name:, action_name:, path:, label_override: nil)
      @controller_name = controller_name.to_s
      @action_name = action_name.to_s
      @path = path.to_s
      @label_override = label_override.presence
    end

    def result
      return Result.new(skip: true) if skip?
      return Result.new(skip: false, label: sign_in_label, link_path: nil) if sign_in_action?

      Result.new(skip: false, label: page_label, link_path: page_link_path)
    end

    private

    attr_reader :controller_name, :action_name, :path, :label_override

    def skip?
      Array(SKIP_ACTIONS[controller_name]).include?(action_name)
    end

    def sign_in_action?
      action_name == "callback" && SIGN_IN_CONTROLLERS.include?(controller_name)
    end

    def sign_in_label
      case controller_name
      when "discord_user_auth" then I18n.t("user_activity.signed_in_discord")
      when "google_user_auth" then I18n.t("user_activity.signed_in_google")
      when "microsoft_user_auth" then I18n.t("user_activity.signed_in_microsoft")
      end
    end

    # Friendly page name. Controllers may provide a richer, context-aware label
    # (e.g. guilds include the guild name) via #activity_label_for_tracking; otherwise
    # fall back to the humanized controller name, which never leaks the action.
    def page_label
      label_override || controller_name.humanize
    end

    def page_link_path
      return nil if path.blank?
      return nil if non_linkable_path?

      path
    end

    def non_linkable_path?
      NON_LINKABLE_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    end
  end
end
