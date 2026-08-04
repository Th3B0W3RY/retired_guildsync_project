module ApplicationHelper
  # Guest marketing top bar — Discord community link (override with COMMUNITY_DISCORD_INVITE_URL e.g. https://discord.gg/…).
  def community_discord_url
    ENV["COMMUNITY_DISCORD_INVITE_URL"].presence ||
      "https://discord.com/widget?id=1499890686021992539&theme=dark"
  end
  # Shown on every layout (including Devise controllers). Must live here — not only
  # ApplicationController#helper_method — because Devise controllers do not inherit ApplicationController.
  def flash_toast_duration_ms
    SiteSetting.flash_toast_duration_ms
  end

  def active_ip_compliance_warning
    return nil unless user_signed_in? && current_user

    current_user.active_ip_conflict_warning
  end

  # Guild for universal "My warnings" sidebar link (route requires persisted :guild_id).
  def sidebar_target_guild_for_my_warnings
    return nil unless user_signed_in?

    candidates = []
    if controller.instance_variable_defined?(:@guild)
      g = controller.instance_variable_get(:@guild)
      candidates << g if g.is_a?(Guild)
    end
    if controller.params[:guild_id].present?
      found = Guild.find_by(id: controller.params[:guild_id])
      candidates << found if found
    end

    candidates.compact.uniq.each do |guild|
      return guild if can_access_my_warnings_page_for_guild?(guild)
    end

    current_user.owned_guilds.not_archived.order(:name).each do |guild|
      return guild if can_access_my_warnings_page_for_guild?(guild)
    end

    current_user.guilds.where(archived_at: nil).distinct.order(:name).each do |guild|
      return guild if can_access_my_warnings_page_for_guild?(guild)
    end

    nil
  end

  def can_access_my_warnings_page_for_guild?(guild)
    return false if guild.blank? || !user_signed_in?

    return true if guild.owner_id == current_user.id

    guild.guild_members.exists?(user_id: current_user.id, status: :active)
  end

  # Top "Alliances" hub: show when the user is tied to an active alliance (any plan), or when
  # their plan can use the alliance hub (e.g. Basic+) even before creating an alliance.
  def show_alliances_top_nav?(user)
    return false unless user

    tied = user.alliance_members.where(status: :active).exists? ||
      user.guilds.joins(:alliance_guild).merge(AllianceGuild.where(status: :active)).exists? ||
      user.owned_guilds.joins(:alliance_guild).merge(AllianceGuild.where(status: :active)).exists?
    return true if tied

    user.plan_allows?(:alliance_hub)
  end

  # Universal menu / dashboard: mirror server rules for guild creation (plan limits, same as GuildsController).
  def show_nav_create_guild?(user)
    return false unless user

    user.can_create_guild?
  end

  # Archive index only lists owned archived guilds; hide nav until user has ever owned a guild.
  def show_nav_archived_guilds?(user)
    return false unless user

    user.owned_guilds.exists?
  end

  # Clean Discord username - removes discriminator (#1234) and extra formatting
  def clean_discord_username(username)
    return nil unless username.present?
    # Remove discriminator (everything after #)
    username.split("#").first.strip
  end

  # Universal menu: display name for "Connected as %{username}" — only when OAuth token exists (see User#discord_connected?).
  # Prefers linked Discord handle, then Discord global name, then site username, then localized fallback.
  def sidebar_discord_username_line(user)
    return nil unless user&.discord_connected?

    conn = user.user_discord_connection
    if conn
      from_conn = clean_discord_username(conn.discord_username).presence
      return from_conn if from_conn
    end

    user.discord_global_name.presence ||
      user.username.presence ||
      I18n.t("sidebar.discord_username_fallback")
  end

  # Figma signed-in sidebar (node 64-*): universal row vs indented guild row
  def sidebar_figma_universal_link(active)
    base = "flex min-h-9 w-full items-center gap-3 rounded-[10px] pl-3 pr-2 text-left text-sm leading-5 transition-colors"
    if active
      "#{base} bg-indigo-400/10 font-medium text-white outline outline-1 outline-offset-[-1px] outline-indigo-400/30"
    else
      "#{base} font-normal text-slate-400 hover:bg-white/5 hover:text-slate-200"
    end
  end

  def sidebar_figma_guild_sublink(active)
    base = "flex min-h-9 w-full items-center gap-2 rounded-[10px] pl-3 pr-2 text-left text-sm leading-5 transition-colors"
    if active
      "#{base} bg-indigo-400/10 font-medium text-white outline outline-1 outline-offset-[-1px] outline-indigo-400/30"
    else
      "#{base} font-normal text-slate-400 hover:bg-white/5 hover:text-slate-200"
    end
  end

  def sidebar_global_dashboard_active?
    controller_name == "home" && action_name == "dashboard"
  end

  def sidebar_feature_requests_active?
    controller_name == "roadmap"
  end

  def sidebar_member_guilds_active?
    controller_name == "member_dashboard"
  end

  def sidebar_guild_dashboard_active?(guild)
    return false if guild.blank?

    controller_name == "guilds" && action_name == "show" && params[:id].to_s == guild.id.to_s
  end

  def sidebar_my_warnings_active?(guild)
    return false if guild.blank?

    controller_name == "guild_my_warnings" && params[:guild_id].to_s == guild.id.to_s
  end

  def sidebar_my_applications_active?
    controller_name == "guild_applications" && action_name == "index"
  end

  def sidebar_apply_to_guild_active?
    controller_name == "guild_applications" && action_name == "new"
  end

  def sidebar_create_guild_active?
    controller_name == "guilds" && %w[new create].include?(action_name)
  end

  def sidebar_archived_guilds_active?
    controller_name == "guild_archives"
  end

  def sidebar_alliances_hub_active?
    controller_name == "alliances"
  end

  def guild_sidebar_logo_tile(guild, size_classes: "h-8 w-8")
    if guild.logo.attached?
      image_tag guild.logo, class: "#{size_classes} shrink-0 rounded-[10px] object-cover", alt: ""
    else
      tag.div(class: "#{size_classes} shrink-0 rounded-[10px] bg-gradient-to-br from-indigo-500 to-purple-600", "aria-hidden": "true")
    end
  end

  def turnstile_enforced?
    TurnstileVerificationService.enforced?
  end

  def turnstile_site_key
    ENV["TURNSTILE_SITE_KEY"].presence
  end

  # Other permission helpers are defined on ApplicationController via helper_method.
end
