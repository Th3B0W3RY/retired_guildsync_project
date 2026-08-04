# frozen_string_literal: true

# Comprehensive search scoped to the current user only:
# - Pages and guild-scoped pages only for guilds the user is a member or owner of.
# - Guild documents only from those same guilds; never other accounts' or guilds' data.
# - Typesense (if enabled) uses build_permission_filter so content is permission-scoped.
class SearchController < ApplicationController
  before_action :authenticate_user!

  # GET /search?q=...
  def index
    query = sanitize_text_input(params[:q]).to_s
    
    if query.blank?
      render json: { results: [], total: 0 }
      return
    end

    begin
      results = perform_search(query)
      render json: results
    rescue => e
      Rails.logger.error "Search failed: #{e.message}"
      render json: { error: t("controllers.search.search_failed") }, status: :internal_server_error
    end
  end

  private

  def perform_search(query)
    all_results = []

    # 1. Search navigation pages (always available) – only pages the user can access
    page_results = search_pages(query)
    all_results.concat(page_results)

    # 2. Search guild document titles – only in guilds the user is a member of (never other accounts)
    document_results = search_guild_documents(query)
    all_results.concat(document_results)

    # 3. Search Typesense content (if enabled) – already permission-scoped via build_permission_filter
    if TypesenseConfig.enabled?
      begin
        content_results = search_typesense(query)
        all_results.concat(content_results)
      rescue => e
        Rails.logger.warn "Typesense search failed, showing page results only: #{e.message}"
      end
    end

    {
      results: all_results.first(30),
      total: all_results.size,
      query: query
    }
  end

  # Guild documents: only guilds the user belongs to; never other users' or guilds' data.
  def search_guild_documents(query)
    return [] if query.blank?
    user_guild_ids = (current_user.guilds.pluck(:id) + current_user.owned_guilds.pluck(:id)).uniq
    return [] if user_guild_ids.empty?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    GuildDocument
      .where(guild_id: user_guild_ids)
      .where("guild_documents.title ILIKE ?", pattern)
      .includes(:guild)
      .limit(15)
      .map do |doc|
        next unless doc.can_view?(current_user)
        {
          id: "doc_#{doc.id}",
          type: "document",
          title: doc.title,
          description: doc.guild.name,
          url: Rails.application.routes.url_helpers.guild_document_path(doc.guild, doc),
          guild_id: doc.guild_id.to_s,
          guild_name: doc.guild.name,
          created_at: doc.created_at&.iso8601,
          highlights: {}
        }
      end.compact
  end

  def search_typesense(query)
    filter = build_permission_filter

    search_params = {
      q: query,
      query_by: "title,description",
      filter_by: filter,
      sort_by: "created_at:desc",
      per_page: 15,
      page: 1,
      highlight_full_fields: "title,description"
    }

    response = TypesenseConfig.client
      .collections[TypesenseConfig.collection_name]
      .documents
      .search(search_params)

    response["hits"].map do |hit|
      doc = hit["document"]
      {
        id: doc["id"],
        type: doc["type"],
        title: doc["title"],
        description: truncate_text(doc["description"], 100),
        url: doc["url"],
        guild_id: doc["guild_id"],
        guild_name: doc["guild_name"],
        created_at: doc["created_at"],
        highlights: extract_highlights(hit["highlights"])
      }
    end
  end

  def search_pages(query)
    query_downcase = query.downcase
    results = []
    
    # Global pages (always accessible to this user only)
    global_pages = [
      { title: "Dashboard", url: dashboard_path, keywords: [ "home", "main", "start", "dashboard" ] },
      { title: "My Guilds", url: my_guilds_path, keywords: [ "guilds", "list", "view", "my guilds" ] },
      { title: "View Guilds", url: my_guilds_path, keywords: [ "guilds", "list", "browse", "all" ] },
      { title: "Create Guild", url: new_guild_path, keywords: [ "new", "create", "add", "guild" ] },
      { title: "Apply to Guild", url: new_guild_application_path, keywords: [ "apply", "join", "application", "guild" ] },
      { title: "My Applications", url: guild_applications_path, keywords: [ "applications", "apply", "pending", "status", "my app" ] },
      { title: "Leaderboard", url: leaderboard_path, keywords: [ "rankings", "top", "scores", "leader" ] },
      { title: "Account Settings", url: account_settings_path, keywords: [ "account", "password", "email", "security", "mfa" ] },
      { title: "Profile Settings", url: profile_settings_path, keywords: [ "avatar", "profile", "display name", "picture" ] },
      { title: "Billing", url: billing_path, keywords: [ "payment", "subscription", "plan", "invoice", "pay" ] },
      { title: "Upgrade Plan", url: upgrade_pricing_path, keywords: [ "upgrade", "premium", "pro", "pricing", "tier" ] },
      { title: "Contact Support", url: contact_support_path, keywords: [ "support", "help", "contact", "ticket", "support page", "help desk" ] },
    ]
    
    global_pages.each do |page|
      if matches_query?(page, query_downcase)
        results << {
          id: "page_#{page[:url].parameterize}",
          type: "page",
          title: page[:title],
          description: nil,
          url: page[:url],
          guild_id: nil,
          guild_name: nil,
          created_at: nil,
          highlights: {}
        }
      end
    end
    
    # Guild-specific pages for each guild the user is a member of
    user_guilds = current_user.guilds + current_user.owned_guilds
    user_guilds.uniq.each do |guild|
      is_owner = guild.owner_id == current_user.id
      can_manage = is_owner || can_manage_guild_settings?(guild)
      
      guild_pages = build_guild_pages(guild, is_owner, can_manage)
      
      guild_pages.each do |page|
        if matches_query?(page, query_downcase)
          results << {
            id: "page_guild_#{guild.id}_#{page[:url].parameterize}",
            type: "page",
            title: "#{page[:title]} - #{guild.name}",
            description: nil,
            url: page[:url],
            guild_id: guild.id.to_s,
            guild_name: guild.name,
            created_at: nil,
            highlights: {}
          }
        end
      end
    end
    
    results
  end

  def build_guild_pages(guild, is_owner, can_manage)
    pages = [
      { title: "Guild Overview", url: "/guilds/#{guild.id}", keywords: ["overview", "home", "main"] },
      { title: "Members", url: "/guilds/#{guild.id}/members", keywords: ["members", "users", "people", "roster"] },
      { title: "Members Gear", url: "/guilds/#{guild.id}/members/gear", keywords: ["gear", "equipment", "stats"] },
      { title: "Guild Documents", url: "/guilds/#{guild.id}/documents", keywords: ["documents", "docs", "wiki", "notes"] },
      { title: "Guild Polls", url: "/guilds/#{guild.id}/polls", keywords: ["polls", "votes", "voting"] },
      { title: "Guild Loot Rolls", url: "/guilds/#{guild.id}/loot_rolls", keywords: ["loot", "rolls", "dice", "random"] },
      { title: "Schedule Events", url: "/guilds/#{guild.id}/events/schedule", keywords: ["events", "schedule", "calendar"] },
      { title: "Schedule Guild Battle", url: "/guilds/#{guild.id}/events/guild-battle", keywords: ["battle", "war", "pvp", "fight"] },
      { title: "File Storage", url: "/guilds/#{guild.id}/storage", keywords: ["files", "storage", "upload", "download"] },
      { title: "Activity Feed", url: "/guilds/#{guild.id}/activity_feed", keywords: ["activity", "feed", "logs", "analytics"] },
    ]
    
    # Owner/admin only pages
    if is_owner || can_manage
      pages.concat([
        { title: "Guild Settings", url: "/guilds/#{guild.id}/settings", keywords: ["settings", "config", "configuration", "options", "preferences"] },
        { title: "Review Applications", url: "/guilds/#{guild.id}/applications", keywords: ["applications", "apply", "join", "requests"] },
        { title: "Invite Members", url: "/guilds/#{guild.id}/members/invite", keywords: ["invite", "add", "recruit"] },
        { title: "Discord Connection", url: "/guilds/#{guild.id}/discord/connect", keywords: ["discord", "bot", "integration", "connect"] },
        { title: "Discord Roles", url: "/guilds/#{guild.id}/discord_roles", keywords: ["roles", "permissions", "discord"] },
      ])
    end
    
    pages
  end

  def matches_query?(page, query_downcase)
    title_lower = page[:title].downcase
    
    # Direct title match
    return true if title_lower.include?(query_downcase)
    
    # Check each word in the title
    title_words = title_lower.split(/\s+/)
    return true if title_words.any? { |word| word.start_with?(query_downcase) }
    
    # Check keywords
    return true if page[:keywords]&.any? do |kw|
      kw.include?(query_downcase) || 
      query_downcase.include?(kw) || 
      kw.start_with?(query_downcase) ||
      query_downcase.split(/\s+/).any? { |q| kw.start_with?(q) || kw.include?(q) }
    end
    
    false
  end

  def build_permission_filter
    user_id = current_user.id.to_s
    
    # Get user's guild memberships
    user_guild_ids = current_user.guilds.pluck(:id).map(&:to_s)
    user_owned_guild_ids = current_user.owned_guilds.pluck(:id).map(&:to_s)
    
    # Get user's Discord role IDs across all guilds
    user_role_ids = get_user_discord_role_ids
    
    # Build filter components
    filters = []
    
    # 1. Public content - anyone can see
    filters << "visibility:=public"
    
    # 2. Guild content - user must be a member
    if user_guild_ids.any?
      guild_filter = user_guild_ids.map { |id| "guild_id:=#{id}" }.join(" || ")
      filters << "(visibility:=guild && (#{guild_filter}))"
    end
    
    # 3. Restricted content - user must have permission
    restricted_conditions = []
    
    # User is the owner
    restricted_conditions << "owner_user_id:=#{user_id}"
    
    # User is explicitly allowed
    restricted_conditions << "allowed_user_ids:=[#{user_id}]"
    
    # User has an allowed role
    if user_role_ids.any?
      role_conditions = user_role_ids.map { |rid| "allowed_role_ids:=[#{rid}]" }.join(" || ")
      restricted_conditions << "(#{role_conditions})"
    end
    
    # User is a member of a guild that owns the content
    if user_guild_ids.any?
      guild_filter = user_guild_ids.map { |id| "guild_id:=#{id}" }.join(" || ")
      restricted_conditions << "(#{guild_filter})"
    end
    
    filters << "(visibility:=restricted && (#{restricted_conditions.join(' || ')}))"
    
    # Combine all filters with OR
    "(#{filters.join(' || ')})"
  end

  def get_user_discord_role_ids
    role_ids = []
    
    # Get all Discord role IDs assigned to this user across guilds
    current_user.guild_members.active.each do |membership|
      role_ids << membership.discord_role_id if membership.discord_role_id.present?
    end
    
    # Also try to get roles from Discord API if connected
    if current_user.user_discord_connection&.discord_user_id.present?
      current_user.guilds.each do |guild|
        next unless guild.guild_discord_setting&.connected?
        
        begin
          discord_service = DiscordService.new
          member = discord_service.get_guild_member(
            guild.guild_discord_setting.discord_guild_id,
            current_user.user_discord_connection.discord_user_id
          )
          role_ids.concat(member["roles"]) if member && member["roles"]
        rescue => e
          Rails.logger.debug "Failed to fetch Discord roles for search: #{e.message}"
        end
      end
    end
    
    role_ids.uniq
  end

  def truncate_text(text, length)
    return "" if text.blank?
    text.length > length ? "#{text[0...length]}..." : text
  end

  def extract_highlights(highlights)
    return {} if highlights.blank?
    
    result = {}
    highlights.each do |highlight|
      field = highlight["field"]
      snippet = highlight["snippet"] || highlight["snippets"]&.first
      result[field] = snippet if snippet.present?
    end
    result
  end
end
