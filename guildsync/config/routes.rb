Rails.application.routes.draw do
  # Skip Devise's default web routes, use our custom controllers
  devise_for :users, skip: [ :sessions, :registrations, :passwords ], controllers: {
    confirmations: "confirmations"
  }

  # Web Routes
  root "home#landing"
  get "/support/documentation", to: "footer_support_links#documentation", as: :footer_support_documentation
  get "/support/contact-link", to: "footer_support_links#contact", as: :footer_support_contact
  get "/support/discord", to: "footer_support_links#discord", as: :footer_support_discord
  get "/privacy", to: "marketing_legal_pages#show", defaults: { kind: "privacy" }, as: :privacy_policy
  get "/terms", to: "marketing_legal_pages#show", defaults: { kind: "terms" }, as: :terms_of_service
  get "/security", to: "marketing_legal_pages#show", defaults: { kind: "security" }, as: :security_page
  get "/disaster-recovery", to: "marketing_legal_pages#show", defaults: { kind: "disaster_recovery" }, as: :disaster_recovery_page

  # Global Search
  get "/search", to: "search#index", as: :search
  get "/pricing", to: "pricing#public_pricing", as: :pricing
  get "/pricing/upgrade", to: "pricing#upgrade", as: :upgrade_pricing
  post "/pricing/select_plan/:id", to: "pricing#select_plan", as: :select_plan
  get "/signup/plan-choice", to: "signup_plan_choices#show", as: :signup_plan_choice
  post "/signup/plan-choice/basic_trial", to: "signup_plan_choices#choose_basic_trial", as: :signup_plan_choice_basic_trial
  post "/signup/plan-choice/paid", to: "signup_plan_choices#choose_paid_plan", as: :signup_plan_choice_paid

  get "/create_account", to: "account_creation#show", as: :create_account
  post "/create_account", to: "account_creation#create"
  get "/create_account/sent", to: "account_creation#sent", as: :create_account_sent
  post "/create_account/resend", to: "account_creation#resend", as: :resend_create_account_verification
  get "/create_account/verify/:token", to: "account_creation#verify", as: :create_account_verify
  get "/create_account/backup_code", to: "account_creation#backup_code", as: :create_account_backup_code
  post "/create_account/backup_code", to: "account_creation#confirm_backup_code"
  get "/create_account/choose_method", to: "account_creation#choose_method", as: :create_account_choose_method
  get "/create_account/standard", to: "account_creation#standard", as: :create_account_standard
  post "/create_account/standard", to: "account_creation#standard_create"
  post "/create_account/discord", to: "account_creation#discord", as: :create_account_discord
  post "/create_account/google", to: "account_creation#google", as: :create_account_google
  post "/create_account/microsoft", to: "account_creation#microsoft", as: :create_account_microsoft

  get "/dashboard", to: "home#dashboard", as: :dashboard
  get "/dashboard/recent_activity", to: "home#recent_activity", as: :dashboard_recent_activity
  get "/dashboard/activity", to: "home#activity", as: :dashboard_activity
  get "/dashboard/stats", to: "home#dashboard_stats", as: :dashboard_stats
  get "/join/complete", to: "join#complete", as: :join_complete
  get "/join/:token", to: "join#show", as: :join_guild
  get "/billing", to: "billing#show", as: :billing
  post "/billing/portal", to: "billing#create_portal_session", as: :billing_portal
  post "/billing/create_checkout_session", to: "billing#checkout", as: :billing_checkout
  post "/billing/change_plan", to: "billing#change_plan", as: :billing_change_plan
  get "/billing/preview_plan_change", to: "billing#preview_plan_change", as: :billing_preview_plan_change
  post "/billing/cancel_subscription", to: "billing#cancel_subscription", as: :billing_cancel_subscription
  post "/billing/resume_subscription", to: "billing#resume_subscription", as: :billing_resume_subscription

  # Marketing homepage feature detail pages (public)
  get "/features/:slug", to: "homepage_features#show", as: :homepage_feature, constraints: { slug: /[a-z][a-z0-9_]*/ }

  # Roadmap & Feature Requests (public index; create/vote require auth)
  get "/roadmap", to: "roadmap#index", as: :roadmap
  get "/roadmap/:id", to: "roadmap#show", as: :roadmap_feature_request
  get "/feature-requests", to: redirect("/roadmap")
  post "/roadmap/requests", to: "roadmap#create", as: :roadmap_requests
  post "/roadmap/requests/:id/vote", to: "roadmap#vote", as: :roadmap_request_vote
  post "/roadmap/requests/:id/comments", to: "roadmap#create_comment", as: :roadmap_request_comments
  delete "/roadmap/comments/:id", to: "roadmap#destroy_comment", as: :roadmap_comment

  # Guild Management
  get "/guilds/new", to: "guilds#new", as: :new_guild
  post "/guilds", to: "guilds#create", as: :guilds
  get "/guilds", to: "guilds#index", as: :my_guilds
  get "/guilds/search", to: "guilds#search"
  get "/guilds/:id/users/search", to: "guilds#search_users", as: :guild_search_users
  post "/guilds/:id/invite_user", to: "guilds#invite_user", as: :guild_invite_user
  get "/guilds/:id", to: "guilds#show", as: :guild
  get "/guilds/:id/settings", to: "guilds#settings", as: :guild_settings
  get "/guilds/:guild_id/warnings/me", to: "guild_warnings#my_status", as: :guild_my_warnings
  get "/guilds/:guild_id/warnings", to: "guild_warnings#index", as: :guild_warnings
  post "/guilds/:guild_id/warnings", to: "guild_warnings#create", as: :guild_warnings_create
  patch "/guilds/:guild_id/warnings/lists", to: "guild_warnings#update_lists", as: :guild_warnings_update_lists
  patch "/guilds/:id", to: "guilds#update", as: :update_guild
  post "/guilds/:id/archive", to: "guilds#archive", as: :archive_guild
  get "/guilds/:id/members", to: "guilds#members", as: :guild_members_list
  post "/guilds/:id/members/tags", to: "guilds#create_member_tag", as: :guild_create_member_tag
  post "/guilds/:id/members/:member_id/tags/:tag_id", to: "guilds#assign_member_tag", as: :guild_assign_member_tag
  delete "/guilds/:id/members/:member_id/tags/:tag_id", to: "guilds#remove_member_tag", as: :guild_remove_member_tag
  delete "/guilds/:id/members/:member_id", to: "guilds#kick_member", as: :guild_kick_member
  post "/guilds/:id/members/bulk_kick", to: "guilds#bulk_kick_members", as: :guild_bulk_kick_members
  patch "/guilds/:id/members/:member_id/update_role", to: "guilds#update_member_role", as: :guild_update_member_role
  post "/guilds/:id/members/bulk_update_roles", to: "guilds#bulk_update_member_roles", as: :guild_bulk_update_member_roles
  get "/guilds/:id/applications", to: "guilds#review_applications", as: :guild_review_applications
  get "/guilds/:id/members/invite", to: "guilds#invite_members", as: :guild_invite_members
  post "/guilds/:id/invite_links", to: "guilds#create_invite_link", as: :guild_invite_links
  get "/guilds/:id/message_center", to: "message_center#index", as: :guild_message_center
  get "/guilds/:id/message_center/search_recipients", to: "message_center#search_recipients", as: :guild_message_center_search
  get "/guilds/:id/message_center/conversation/:recipient_id", to: "message_center#conversation", as: :guild_message_center_conversation
  post "/guilds/:id/message_center/send", to: "message_center#create", as: :guild_message_center_send

  # Guild File Storage (storage, file_entries, folders – S3/local Active Storage)
  get "/guilds/:guild_id/storage", to: "storage#show", as: :guild_storage
  post "/guilds/:guild_id/file_entries", to: "file_entries#create", as: :guild_file_entries
  patch "/guilds/:guild_id/file_entries/bulk_move", to: "file_entries#bulk_move", as: :bulk_move_guild_file_entries
  delete "/guilds/:guild_id/file_entries/bulk_destroy", to: "file_entries#bulk_destroy", as: :bulk_destroy_guild_file_entries
  get "/guilds/:guild_id/file_entries/:id/download", to: "file_entries#download", as: :download_guild_file_entry
  delete "/guilds/:guild_id/file_entries/:id", to: "file_entries#destroy", as: :guild_file_entry
  post "/guilds/:guild_id/folders", to: "folders#create", as: :guild_folders
  patch "/guilds/:guild_id/folders/:id", to: "folders#update", as: :update_guild_folder
  delete "/guilds/:guild_id/folders/:id", to: "folders#destroy", as: :guild_folder

  # Guild Documents
  resources :guilds do
    resources :documents, controller: "guild_documents" do
      member do
        get :share   # public view
      end
      collection do
        post :autosave
        post :upload_image
        post :create_folder
        patch :update_folder
        delete :destroy_folder
      end
    end

    # Polls
    resources :polls, controller: "polls" do
      member do
        post :vote
        post :post_to_discord
      end
    end

    # Loot Rolls
    resources :loot_rolls, controller: "loot_rolls" do
      member do
        post :close
        post :force_reroll
      end
    end
  end
  get "/guilds/:id/events/schedule", to: "guilds#schedule_events", as: :guild_schedule_events
  get "/guilds/:id/members/gear", to: "guilds#members_gear", as: :guild_members_gear
  get "/guilds/:id/members/stats/:user_id", to: "guilds#member_stats", as: :guild_member_stats
  patch "/guilds/:id/members/stats/:user_id/fields", to: "guilds#update_member_stats_fields", as: :guild_member_stats_fields
  get "/guilds/:id/discord/connect", to: "discord_connections#show", as: :guild_connect_discord
  patch "/guilds/:id/discord/channels", to: "guilds#update_discord_channels", as: :guild_update_discord_channels
  get "/guilds/:id/activity_feed", to: "activity_feed#index", as: :guild_activity_feed
  get "/guilds/:id/activity_feed/export", to: "activity_feed#export", as: :guild_activity_feed_export
  get "/guilds/:id/analytics", to: redirect { |params, _req| "/guilds/#{params[:id]}/activity_feed" }

  # Guild owner — alliance invite / join request (per-guild; not on /alliances hub)
  get "/guilds/:guild_id/alliance_invites/pending", to: "guild_alliance_invites#pending", as: :guild_alliance_invites_pending
  get "/guilds/:guild_id/alliance_join_requests/new", to: "guild_alliance_join_requests#new", as: :new_guild_alliance_join_request
  get "/guilds/:guild_id/alliance_join_status", to: "guild_alliance_join_requests#status", as: :guild_alliance_join_status

  # Alliance routes
  get "alliances/guild_search", to: "alliances#guild_search", as: :alliances_guild_search

  resources :alliances, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    member do
      post :leave
      post :kick_guild
    end

    resources :alliance_members, only: [ :index ] do
      collection do
        delete :remove
        delete :bulk_remove
        post :create_tag
        post :assign_tag
        delete :remove_tag
      end
    end

    resources :alliance_invites, only: [ :index, :create ] do
      collection do
        get :guild_search
      end
      member do
        post :accept
        post :decline
      end
    end

    resources :alliance_join_requests, only: [ :index, :create ] do
      member do
        post :accept
        post :decline
      end
    end

    resources :alliance_events do
      member do
        post :rsvp
      end
    end

    resources :alliance_polls do
      member do
        post :vote
      end
    end

    resources :alliance_loot_rolls do
      member do
        post :close
        post :enter
      end
    end

    resources :alliance_disband_votes, only: [ :index, :create ]

    resources :alliance_messages, only: [ :index, :create ]
  end

  get "/alliances/:alliance_id/activity_feed", to: "alliance_activity_feeds#index", as: :alliance_activity_feed
  # Must be before `export` so `/export.json` is not matched as `export` with format :json
  get "/alliances/:alliance_id/activity_feed/export.json", to: "alliance_activity_feeds#export_json", as: :alliance_activity_feed_export_json
  get "/alliances/:alliance_id/activity_feed/export", to: "alliance_activity_feeds#export", as: :alliance_activity_feed_export

  # React roles routes
  patch  "/guilds/:id/react_roles",        to: "react_roles#update",  as: :guild_react_roles
  post   "/guilds/:id/react_roles/deploy", to: "react_roles#deploy",  as: :guild_react_roles_deploy
  delete "/guilds/:id/react_roles",        to: "react_roles#destroy", as: :guild_react_roles_destroy
  get    "/guilds/:id/react_roles/emojis", to: "react_roles#emojis",  as: :guild_react_roles_emojis

  # Game management routes
  patch "/guilds/:id/games", to: "guilds#update_games", as: :guild_update_games
  get "/games/search", to: "games#search", as: :games_search
  post "/games/suggest", to: "games#suggest", as: :games_suggest

  # Gear management routes
  post "/guilds/:id/gear/upload", to: "gear#upload", as: :guild_gear_upload
  get "/guilds/:id/gear/:user_id/screenshot", to: "gear#screenshot", as: :guild_gear_screenshot
  get "/guilds/:id/gear/:user_id", to: "gear#show", as: :guild_gear_show
  post "/guilds/:id/gear/request", to: "gear#request_update", as: :guild_gear_request
  post "/guilds/:id/gear/request_bulk", to: "gear#request_bulk", as: :guild_gear_request_bulk

  # Discord Role Syncing
  get "/guilds/:id/discord_roles", to: "discord_roles#index", as: :guild_discord_roles
  post "/guilds/:id/discord_roles/sync", to: "discord_roles#sync", as: :guild_discord_roles_sync
  delete "/guilds/:id/discord_roles/sync/:role_id", to: "discord_roles#destroy", as: :guild_discord_roles_unsync
  post "/guilds/:id/discord_roles/sync_all", to: "discord_roles#sync_all", as: :guild_discord_roles_sync_all
  delete "/guilds/:id/discord_roles/sync_all", to: "discord_roles#destroy_all", as: :guild_discord_roles_unsync_all

  # Discord Connections (per-guild)
  resources :guilds do
    resource :discord_connection, only: [ :show, :destroy ], controller: "discord_connections"
    resources :discord_events, only: [ :new, :create, :show, :destroy ], controller: "discord_events"
  end

  # OAuth start
  get "/guilds/:guild_id/discord_connection/new", to: "discord_connections#create", as: :new_guild_discord_connection

  # OAuth callback (handles both user OAuth and bot authorization)
  get "/discord/oauth/callback", to: "discord_connections#oauth_callback", as: :discord_oauth_callback

  # Server selection
  get "/guilds/:guild_id/discord_connection/select_server", to: "discord_connections#select_server", as: :select_discord_server
  post "/guilds/:guild_id/discord_connection/connect_server", to: "discord_connections#connect_server", as: :connect_discord_server

  # Leaderboard
  get "/leaderboard", to: "leaderboard#index", as: :leaderboard

  # Discord User Auth (Login/Linking)
  get "/auth/discord", to: "discord_user_auth#start", as: :discord_login
  post "/auth/discord", to: "discord_user_auth#start"
  get "/auth/discord/callback", to: "discord_user_auth#callback", as: :discord_callback
  get "/auth/discord/verify", to: "discord_user_auth#verify_session", as: :discord_verify_session
  get "/auth/discord/success", to: "discord_user_auth#success", as: :discord_success
  post "/auth/discord/disconnect", to: "discord_user_auth#disconnect", as: :discord_disconnect
  patch "/auth/discord/toggle_method", to: "discord_user_auth#toggle_auth_method", as: :discord_toggle_auth_method

  get "/auth/google", to: "google_user_auth#start", as: :google_login
  post "/auth/google", to: "google_user_auth#start"
  get "/auth/google/callback", to: "google_user_auth#callback", as: :google_callback
  get "/auth/google/verify", to: "google_user_auth#verify_session", as: :google_verify_session

  get "/auth/microsoft", to: "microsoft_user_auth#start", as: :microsoft_login
  post "/auth/microsoft", to: "microsoft_user_auth#start"
  get "/auth/microsoft/callback", to: "microsoft_user_auth#callback", as: :microsoft_callback
  get "/auth/microsoft/verify", to: "microsoft_user_auth#verify_session", as: :microsoft_verify_session

  # Member dashboard
  get "/member/dashboard", to: "member_dashboard#index", as: :member_dashboard

  # Guild applications
  resources :guild_applications, only: [ :index, :new, :create ] do
    post :message, on: :member
    patch :accept, on: :member, action: :accept
    patch :reject, on: :member, action: :reject
  end

  resources :guild_archives, only: [ :index ] do
    member do
      post :unarchive
      delete :destroy
    end
  end

  # Guild invites
  resources :guild_invites, only: [ :show ] do
    member do
      patch :accept
      patch :deny
      patch :dismiss
    end
  end

  # Support
  get "/support/contact", to: "support#contact", as: :contact_support

  # Subscriptions
  get "/subscribe", to: "subscriptions#create", as: :subscribe
  post "/subscribe", to: "subscriptions#create"
  get "/subscriptions/success", to: "subscriptions#success", as: :success_subscriptions

  # Stripe Webhooks
  post "/stripe/webhooks", to: "stripe/webhooks#receive"

  # Discord Interactions
  post "/discord/interactions", to: "discord#interactions"

  # Discord Webhooks (legacy event signup interactions – keep for backward compatibility)
  post "/discord/webhooks", to: "discord_webhooks#interactions"
  post "/discord/event_signups/webhook", to: "discord_event_signups#webhook", as: :discord_event_signups_webhook

  # Profile management
  patch "/profile/avatar", to: "profiles#update_avatar", as: :update_avatar
  delete "/profile/avatar", to: "profiles#remove_avatar", as: :remove_avatar

  # Profile completion (for Discord users)
  get "/profile/complete", to: "profile_completion#show", as: :complete_profile
  patch "/profile/complete", to: "profile_completion#update"

  # Settings pages
  get "/account/settings", to: "settings#account", as: :account_settings
  get "/profile/settings", to: "settings#profile", as: :profile_settings
  patch "/profile/settings/username", to: "settings#update_profile_username", as: :profile_settings_username
  post "/profile/settings/email_verification", to: "settings#request_profile_email_verification", as: :profile_settings_email_verification
  get "/profile/email/verify", to: "profile_email_verifications#show", as: :verify_profile_email
  get "/release-notes", to: "settings#release_notes", as: :release_notes
  patch "/settings/locale", to: "settings#update_locale", as: :update_locale_settings

  post "/account/deletion/send_code", to: "account_deletions#send_code", as: :account_deletion_send_code
  post "/account/deletion/confirm", to: "account_deletions#confirm", as: :account_deletion_confirm

  # Backup codes (generate from account settings; verify from forgot-password flow)
  resources :backup_codes, only: [], path: "backup_codes" do
    collection do
      post :generate
      post :regenerate
      post :verify
    end
  end

  # Account recovery (after backup code verification: set new password + optional MFA reset)
  get "/account/recover", to: "recoveries#edit", as: :recover_account
  put "/account/recover", to: "recoveries#update"
  patch "/account/recover", to: "recoveries#update"

  # Admin: Game management
  resources :games, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    member do
      patch :toggle_active
    end
  end

  # Admin Panel (separate authentication)
  namespace :admin do
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"
    root to: "dashboard#index"

    # Game management
    resources :games, only: [ :index, :destroy ] do
      collection do
        get "pending", to: "games#pending", as: :pending_games
        get "search", to: "games#search", as: :search
      end
      member do
        post "approve", to: "games#approve", as: :approve_game
        post "deny", to: "games#deny", as: :deny_game
        delete "reject", to: "games#reject", as: :reject_game
      end
    end

    # User management
    resources :users, only: [ :index, :show ] do
      collection do
        get "search", to: "users#search", as: :search
      end
      member do
        post :reactivate_account
      end
      patch "trial", to: "users#update_trial", as: :update_trial, on: :member
    end

    resources :soft_deleted_records, path: "soft-deleted-records", only: [ :index ] do
      member do
        patch :restore
        delete :purge
      end
    end

    # Database queries
    resources :queries, only: [ :index ] do
      post "execute", on: :collection
    end

    get "pricing-plan-features", to: "pricing_plan_features#edit", as: :edit_pricing_plan_features
    patch "pricing-plan-features", to: "pricing_plan_features#update", as: :pricing_plan_features

    get "landing-compare", to: "landing_compare#edit", as: :edit_landing_compare
    patch "landing-compare", to: "landing_compare#update", as: :landing_compare

    resources :landing_user_feedbacks, path: "landing-user-feedbacks", except: [ :show ] do
      collection do
        patch :reorder
        patch :update_carousel_settings, path: "carousel-settings"
      end
    end

    resources :homepage_feature_cards, path: "homepage-feature-cards", except: [ :show ] do
      collection do
        patch :reorder
        post :upload_image
      end
    end

    resources :marketing_legal_pages, path: "marketing-legal-pages", only: [ :edit, :update ]

    get "fontawesome-free-icons", to: "fontawesome_free_icons#index", as: :fontawesome_free_icons, defaults: { format: :json }

    # Subscription management
    resources :subscriptions, only: [] do
      collection do
        get "paying", to: "subscriptions#paying_users", as: :paying_users
        get "trials", to: "subscriptions#trial_users", as: :trial_users
        get "paying/search", to: "subscriptions#search_paying", as: :search_paying
        get "trials/search", to: "subscriptions#search_trials", as: :search_trials
      end
    end

    # Admin Audit Logs
    resources :audit_logs, only: [ :index, :show ]

    # OCR Request Counts
    get "ocr-requests", to: "ocr_requests#index", as: :ocr_requests
    get "ocr-requests/export", to: "ocr_requests#export", as: :ocr_requests_export
    get "ocr-requests/:user_id", to: "ocr_requests#show", as: :ocr_request_user
    post "ocr-requests/:user_id/adjust", to: "ocr_requests#adjust_usage", as: :ocr_request_adjust
    post "ocr-requests/:user_id/toggle_lock", to: "ocr_requests#toggle_lock", as: :ocr_request_toggle_lock
    post "ocr-requests/:user_id/toggle_unlock", to: "ocr_requests#toggle_unlock", as: :ocr_request_toggle_unlock
    post "ocr-requests/:user_id/reset_period", to: "ocr_requests#reset_period", as: :ocr_request_reset_period
    patch "ocr-requests/:user_id/notes", to: "ocr_requests#update_notes", as: :ocr_request_notes
    post "ocr-requests/bulk", to: "ocr_requests#bulk_action", as: :ocr_requests_bulk

    # System Monitoring
    get "system-monitoring/metrics", to: "system_monitoring#metrics", as: :system_monitoring_metrics
    get "system-monitoring", to: "system_monitoring#show", as: :system_monitoring

    # Database backups (read-only status; opt-in S3 dumps)
    get "database-backups", to: "database_backups#show", as: :database_backups

    # Error Tracker
    resources :errors, controller: "errors", only: [ :index, :show, :destroy ] do
      collection do
        post "bulk", to: "errors#bulk_action", as: :bulk
      end
      post "resolve", on: :member
    end

    # Guild Transfers
    resources :guild_transfers, only: [] do
      collection do
        get "new/:guild_id", to: "guild_transfers#new", as: :new_guild_transfer
        post "create", to: "guild_transfers#create", as: :create_guild_transfer
      end
    end

    # Feature Requests (admin)
    resources :feature_requests, only: [ :index, :edit, :update, :destroy ], path: "roadmap" do
      member do
        patch :pin
        patch :move
      end
      collection do
        patch :reorder
      end
    end

    get "beta-features", to: "beta_features#index", as: :beta_features
    post "beta-features/:user_id/enable", to: "beta_features#enable", as: :beta_feature_enable
    post "beta-features/:user_id/disable", to: "beta_features#disable", as: :beta_feature_disable

    get "feature-abusers", to: "feature_abusers#index", as: :feature_abusers
    post "feature-abusers/:user_id/lock", to: "feature_abusers#lock", as: :feature_abuser_lock
    post "feature-abusers/:user_id/unlock", to: "feature_abusers#unlock", as: :feature_abuser_unlock

    # User Compliance
    resources :user_compliance, only: [] do
      collection do
        post "force_logout/:user_id", to: "user_compliance#force_logout", as: :force_logout
        post "reset_mfa/:user_id", to: "user_compliance#reset_mfa", as: :reset_mfa
        post "reset_email/:user_id", to: "user_compliance#reset_email", as: :reset_email
        post "disable_account/:user_id", to: "user_compliance#disable_account", as: :disable_account
        post "enable_account/:user_id", to: "user_compliance#enable_account", as: :enable_account
        get "login_history/:user_id", to: "user_compliance#login_history", as: :login_history
      end
    end

    # Site Settings
    get "settings/release-notes", to: "site_settings#release_notes", as: :release_notes_settings
    patch "settings/release-notes", to: "site_settings#update_release_notes", as: :update_release_notes_settings
    get "homepage-footer", to: "homepage_footer_settings#show", as: :homepage_footer_settings
    patch "homepage-footer", to: "homepage_footer_settings#update", as: :update_homepage_footer_settings

    get "settings/flash", to: "flash_settings#show", as: :flash_settings
    patch "settings/flash", to: "flash_settings#update", as: :update_flash_settings
    post "settings/flash/test", to: "flash_settings#test", as: :test_flash_settings

    # Error Notification Settings
    get "settings/error-notifications", to: "error_settings#show", as: :error_notification_settings
    patch "settings/error-notifications", to: "error_settings#update", as: :update_error_notification_settings

    # Error Batch Reports
    resources :error_batch_reports, only: [ :index, :show ], path: "error-batch-reports" do
      collection do
        post :run_now
      end
    end
    get "ui-design-system", to: "ui_design_system#show", as: :ui_design_system

    # Content Moderation
    resources :content_moderation, only: [ :index ], path: "content_moderation" do
      collection do
        post "approve", to: "content_moderation#approve", as: :approve_content
        post "hide", to: "content_moderation#hide", as: :hide_content
        post "soft_delete", to: "content_moderation#soft_delete", as: :soft_delete_content
        post "add_blocked_word", to: "content_moderation#add_blocked_word", as: :add_blocked_word
        delete "remove_blocked_word/:id", to: "content_moderation#remove_blocked_word", as: :remove_blocked_word
        post "run_health_check", to: "content_moderation#run_health_check", as: :run_health_check
        post "trigger_profanity_update", to: "content_moderation#trigger_profanity_update", as: :trigger_profanity_update
      end
    end
  end

  # Custom Devise web routes
  as :user do
    # Sessions
    get    "/login",   to: "sessions#new",     as: :login
    post   "/sign_in", to: "sessions#create", as: :sign_in
    delete "/sign_out", to: "sessions#destroy", as: :sign_out

    # Registrations
    get  "/sign_up", to: "registrations#new",    as: :sign_up
    post "/sign_up", to: "registrations#create"

    # Passwords
    get  "/password/new",  to: "passwords#new",   as: :new_password
    post "/password",      to: "passwords#create", as: :password
    get  "/password/edit", to: "passwords#edit",  as: :edit_password
    patch "/password",     to: "passwords#update"
    put   "/password",     to: "passwords#update"

    # MFA Setup (mandatory after registration)
    get  "/mfa/setup", to: "mfa_setup#show", as: :mfa_setup
    post "/mfa/verify_setup", to: "mfa_setup#verify", as: :verify_mfa_setup

    # MFA Verification (required on login)
    get  "/mfa/verify", to: "mfa_verification#show", as: :mfa_verification
    post "/mfa/verify", to: "mfa_verification#verify"
  end

  # API Routes
  namespace :api do
    namespace :v1 do
      # Authentication
      post "/auth/sign_up", to: "auth#sign_up"
      post "/auth/sign_in", to: "auth#sign_in"
      delete "/auth/sign_out", to: "auth#sign_out"
      get "/auth/me", to: "auth#me"

      # Test-only: generate a real password reset token (gated inside the action)
      post "/auth/reset_password_token", to: "auth#test_reset_password_token" if Rails.env.test? || ENV["INTEGRATION_TESTS"] == "1"

      # Users
      resources :users, only: [ :show, :update ] do
        get :guilds, on: :member
        post :archive, on: :member
      end

      # Guilds
      resources :guilds do
        resources :members, controller: "guild_members", only: [ :index, :show, :create, :destroy, :update ]
        resources :events, only: [ :index, :create ]
        resources :applications, controller: "guild_applications", only: [ :index, :show, :create, :update ]
        resources :invites, controller: "guild_invites", only: [ :index, :create, :destroy ]

        # Discord integration
        get "discord/channels", to: "discord#channels"
        patch "discord/channels", to: "discord#update_channels"
        post "discord/events/:event_id/signup", to: "discord#signup_event"
      end

      # Events
      resources :events, only: [ :show, :update, :destroy ] do
        post :participate, on: :member
        delete :participate, on: :member, action: :unparticipate
        get :participants, on: :member
      end

      # Guild invite responses (invited user actions)
      resources :guild_invites, only: [] do
        member do
          patch :accept
          patch :deny
        end
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Sidekiq Web UI (admin only)
  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq"
end
