namespace :discord do
  desc "Register ALL GuildSync slash commands with Discord (replaces the full set atomically)"
  task register_commands: :environment do
    require "rest-client"

    application_id = ENV["DISCORD_APPLICATION_ID"] || ENV["DISCORD_CLIENT_ID"]
    bot_token      = ENV["DISCORD_BOT_TOKEN"]
    
    unless application_id && bot_token
      puts "Error: DISCORD_APPLICATION_ID (or DISCORD_CLIENT_ID) and DISCORD_BOT_TOKEN must be set"
      exit 1
    end

    # -------------------------------------------------------------------------
    # Discord option type constants (for readability)
    # -------------------------------------------------------------------------
    # 1 = SUB_COMMAND, 2 = SUB_COMMAND_GROUP, 3 = STRING, 4 = INTEGER,
    # 5 = BOOLEAN, 6 = USER, 7 = CHANNEL, 8 = ROLE, 9 = MENTIONABLE,
    # 10 = NUMBER, 11 = ATTACHMENT
    # -------------------------------------------------------------------------

    event_type_choices = [
      { name: "PvP",                  value: "pvp" },
      { name: "Guild Scrim",          value: "guild_scrim" },
      { name: "GvG",                  value: "gvg" },
      { name: "Regular Scrim",        value: "regular_scrim" },
      { name: "PvE Event",            value: "pve_event" },
      { name: "World Boss",           value: "world_boss" },
      { name: "Guild Questing",       value: "guild_questing_time" }
    ]

    month_choices = [
      { name: "January",   value: 1 },  { name: "February",  value: 2 },
      { name: "March",     value: 3 },  { name: "April",     value: 4 },
      { name: "May",       value: 5 },  { name: "June",      value: 6 },
      { name: "July",      value: 7 },  { name: "August",    value: 8 },
      { name: "September", value: 9 },  { name: "October",   value: 10 },
      { name: "November",  value: 11 }, { name: "December",  value: 12 }
    ]

    hour_choices = (1..12).map { |h| { name: h.to_s, value: h } }

    minute_choices = (0..55).step(5).map { |m| { name: format("%02d", m), value: m } }

    ampm_choices = [
      { name: "AM", value: "AM" },
      { name: "PM", value: "PM" }
    ]
    
    commands = [
      # ------------------------------------------------------------------
      # EXISTING: /signup  (unchanged)
      # ------------------------------------------------------------------
      {
        name:        "signup",
        description: "Sign up for a GuildSync event",
        options: [
          {
            type:        3,
            name:        "role",
            description: "Your role for the event",
            required:    true,
            choices: [
              { name: "DPS",    value: "dps" },
              { name: "Tank",   value: "tank" },
              { name: "Healer", value: "healer" },
              { name: "Ranged", value: "ranged" }
            ]
          },
          {
            type:        4,
            name:        "event",
            description: "GuildSync event ID (optional — inferred from context when possible)",
            required:    false
          }
        ]
      },

      # ------------------------------------------------------------------
      # EXISTING: /gear  (unchanged)
      # ------------------------------------------------------------------
      {
        name:        "gear",
        description: "Manage gear snapshots",
        options: [
          {
            type:        1,
            name:        "upload",
            description: "Upload a gear screenshot",
            options: [
              {
                type:        11,
                name:        "image",
                description: "Gear screenshot image",
                required:    false
              }
            ]
          },
          {
            type:        1,
            name:        "my",
            description: "View your latest gear snapshot"
          },
          {
            type:        1,
            name:        "request",
            description: "Request a gear update from a specific member (Officer+)",
            options: [
              {
                type:        6,
                name:        "user",
                description: "Member to request gear from",
                required:    true
              }
            ]
          },
          {
            type:        1,
            name:        "request_missing",
            description: "Request gear from all missing or outdated members (Officer+)",
            options: [
              {
                type:        3,
                name:        "status",
                description: "Filter by gear status",
                required:    false,
                choices: [
                  { name: "Missing",               value: "missing" },
                  { name: "Outdated",              value: "outdated" },
                  { name: "All (Missing+Outdated)", value: "all" }
                ]
              }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 1: /poll
      # ------------------------------------------------------------------
      {
        name:        "poll",
        description: "Manage guild polls",
        options: [
          {
            type:        1,
            name:        "create",
            description: "Create a new poll and post it to the polls channel (Officer+)",
            options: [
              { type: 3, name: "question",       description: "Poll question",                          required: true },
              { type: 3, name: "option_a",       description: "Option A (maps to Yes vote)",            required: true },
              { type: 3, name: "option_b",       description: "Option B (maps to No vote)",             required: true },
              { type: 3, name: "option_c",       description: "Option C (maps to Maybe vote)",          required: false },
              { type: 4, name: "deadline_hours", description: "Hours until poll closes (default: 24)",  required: false },
              { type: 5, name: "anonymous",      description: "Hide voter names? (default: false)",     required: false }
            ]
          },
          {
            type:        1,
            name:        "list",
            description: "List all active polls in this guild"
          },
          {
            type:        1,
            name:        "results",
            description: "View results of a specific poll",
            options: [
              { type: 4, name: "poll_id", description: "Poll ID (from /poll list)", required: true }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 1: /loot
      # ------------------------------------------------------------------
      {
        name:        "loot",
        description: "Manage loot rolls",
        options: [
          {
            type:        1,
            name:        "create",
            description: "Create a loot roll and post it to the loot rolls channel (Officer+)",
            options: [
              { type: 3, name: "item_name",        description: "Item or loot name",                         required: true },
              { type: 4, name: "min",              description: "Minimum roll value (default: 1)",           required: false },
              { type: 4, name: "max",              description: "Maximum roll value (default: 100)",         required: false },
              { type: 4, name: "deadline_minutes", description: "Minutes until roll closes (default: none)", required: false }
            ]
          },
          {
            type:        1,
            name:        "list",
            description: "List all open loot rolls in this guild"
          },
          {
            type:        1,
            name:        "view",
            description: "View the current status and rolls for a loot roll",
            options: [
              { type: 4, name: "loot_id", description: "Loot roll ID (from /loot list)", required: true }
            ]
          },
          {
            type:        1,
            name:        "close",
            description: "Close a loot roll and determine the winner (Officer+)",
            options: [
              { type: 4, name: "loot_id", description: "Loot roll ID (from /loot list)", required: true }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 1: /event
      # ------------------------------------------------------------------
      {
        name:        "event",
        description: "Manage guild events",
        options: [
          {
            type:        1,
            name:        "create",
            description: "Create a Discord event and post signup message (Officer+)",
            options: [
              { type: 3, name: "title",        description: "Event title",              required: true },
              { type: 4, name: "month",        description: "Month",                    required: true, choices: month_choices },
              { type: 4, name: "day",          description: "Day of the month (1-31)",  required: true },
              { type: 4, name: "hour",         description: "Hour (1-12)",              required: true, choices: hour_choices },
              { type: 4, name: "minute",       description: "Minute",                   required: true, choices: minute_choices },
              { type: 3, name: "ampm",         description: "AM or PM",                required: true, choices: ampm_choices },
              { type: 3, name: "description",  description: "Event description",        required: false },
              { type: 3, name: "type",         description: "Event type",               required: false, choices: event_type_choices },
              { type: 3, name: "location",     description: "In-game location",         required: false },
              { type: 3, name: "squad_leader", description: "Squad leader name",        required: false }
            ]
          },
          {
            type:        1,
            name:        "list",
            description: "List upcoming events in this guild"
          },
          {
            type:        1,
            name:        "view",
            description: "View event details and signup counts",
            options: [
              { type: 4, name: "event_id", description: "Event ID (from /event list)", required: true }
            ]
          },
          {
            type:        1,
            name:        "cancel",
            description: "Cancel an event and remove it from Discord (Officer+)",
            options: [
              { type: 4, name: "event_id", description: "Event ID (from /event list)", required: true }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 1: /invite
      # ------------------------------------------------------------------
      {
        name:        "invite",
        description: "Invite a Discord user to this guild via DM",
        options: [
          { type: 6, name: "user",    description: "Discord user to invite",            required: true },
          { type: 3, name: "message", description: "Optional personal message to include", required: false }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 2: /member
      # ------------------------------------------------------------------
      {
        name:        "member",
        description: "Manage guild members",
        options: [
          {
            type:        1,
            name:        "list",
            description: "List guild members",
            options: [
              {
                type:        3,
                name:        "role",
                description: "Filter by role",
                required:    false,
                choices: [
                  { name: "Member",    value: "member" },
                  { name: "Moderator", value: "moderator" },
                  { name: "Admin",     value: "admin" }
                ]
              }
            ]
          },
          {
            type:        1,
            name:        "info",
            description: "View a member's details",
            options: [
              { type: 6, name: "user", description: "Guild member", required: true }
            ]
          },
          {
            type:        1,
            name:        "kick",
            description: "Remove a member from the guild (Officer+)",
            options: [
              { type: 6, name: "user",   description: "Member to kick", required: true },
              { type: 3, name: "reason", description: "Reason",         required: false }
            ]
          },
          {
            type:        1,
            name:        "role",
            description: "Change a member's role (Officer+)",
            options: [
              { type: 6, name: "user", description: "Member to update", required: true },
              {
                type:        3,
                name:        "role",
                description: "New role",
                required:    true,
                choices: [
                  { name: "Member",    value: "member" },
                  { name: "Moderator", value: "moderator" },
                  { name: "Admin",     value: "admin" }
                ]
              }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 2: /guild
      # ------------------------------------------------------------------
      {
        name:        "guild",
        description: "View guild information and settings",
        options: [
          { type: 1, name: "info",     description: "View guild info (member count, plan, games)" },
          { type: 1, name: "settings", description: "View guild settings (Owner only)" },
          { type: 1, name: "channels", description: "View configured Discord channels (Officer+)" }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 2: /application
      # ------------------------------------------------------------------
      {
        name:        "application",
        description: "Manage guild applications (Officer+)",
        options: [
          { type: 1, name: "list",   description: "List pending guild applications" },
          {
            type:        1,
            name:        "view",
            description: "View a specific application",
            options: [
              { type: 4, name: "application_id", description: "Application ID (from /application list)", required: true }
            ]
          },
          {
            type:        1,
            name:        "accept",
            description: "Accept an application and add the user to the guild",
            options: [
              { type: 4, name: "application_id", description: "Application ID (from /application list)", required: true }
            ]
          },
          {
            type:        1,
            name:        "reject",
            description: "Reject an application",
            options: [
              { type: 4, name: "application_id", description: "Application ID (from /application list)", required: true },
              { type: 3, name: "reason",         description: "Reason for rejection",                    required: false }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 3: /docs
      # ------------------------------------------------------------------
      {
        name:        "docs",
        description: "Browse and search guild documents",
        options: [
          {
            type:        1,
            name:        "list",
            description: "List guild documents",
            options: [
              { type: 3, name: "folder", description: "Folder name to filter by", required: false }
            ]
          },
          {
            type:        1,
            name:        "view",
            description: "View a guild document (truncated preview)",
            options: [
              { type: 4, name: "doc_id", description: "Document ID (from /docs list)", required: true }
            ]
          },
          {
            type:        1,
            name:        "search",
            description: "Search guild documents by keyword",
            options: [
              { type: 3, name: "query", description: "Search terms", required: true }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 3: /leaderboard
      # ------------------------------------------------------------------
      {
        name:        "leaderboard",
        description: "Show the top 10 event participation leaderboard for this guild"
      },

      # ------------------------------------------------------------------
      # PHASE 3: /activity
      # ------------------------------------------------------------------
      {
        name:        "activity",
        description: "Show the last 10 guild activity feed entries"
      },

      # ------------------------------------------------------------------
      # PHASE 3: /profile
      # ------------------------------------------------------------------
      {
        name:        "profile",
        description: "View guild member profiles",
        options: [
          { type: 1, name: "me",   description: "View your own GuildSync profile" },
          {
            type:        1,
            name:        "view",
            description: "View another member's GuildSync profile",
            options: [
              { type: 6, name: "user", description: "Guild member to view", required: true }
            ]
          }
        ]
      },

      # ------------------------------------------------------------------
      # /alliance — cross-guild alliances (web hub + join requests)
      # ------------------------------------------------------------------
      {
        name:        "alliance",
        description: "GuildSync alliances: info, web hub link, and pending join requests",
        options: [
          { type: 1, name: "info",     description: "Show this guild's alliance and a link to the web hub" },
          { type: 1, name: "hub",      description: "Get the GuildSync alliances page URL" },
          { type: 1, name: "requests", description: "List pending alliance join requests (leader / GM / officers)" }
        ]
      },

      # ------------------------------------------------------------------
      # PHASE 3: /help
      # ------------------------------------------------------------------
      {
        name:        "help",
        description: "List all available GuildSync slash commands"
      }
    ]
    
    url = "https://discord.com/api/v10/applications/#{application_id}/commands"
    
    begin
      response = RestClient.put(
        url,
        commands.to_json,
        {
          "Authorization" => "Bot #{bot_token}",
          "Content-Type"  => "application/json"
        }
      )
      
      registered = JSON.parse(response.body)
      puts "✓ #{registered.length} commands registered successfully (HTTP #{response.code})"
      registered.each { |c| puts "  • /#{c['name']}" }
    rescue RestClient::ExceptionWithResponse => e
      puts "Error registering commands: #{e.response.code} - #{e.response.body}"
      exit 1
    rescue => e
      puts "Error: #{e.message}"
      exit 1
    end
  end

  # Legacy alias kept for backward compatibility
  desc "[Deprecated] Use discord:register_commands instead"
  task register_gear_commands: :register_commands
end

