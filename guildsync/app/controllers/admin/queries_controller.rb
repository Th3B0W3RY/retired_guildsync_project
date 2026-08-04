# frozen_string_literal: true

module Admin
  class QueriesController < BaseController
    require "digest"

    QUERIES_INDEX_MAIN_FRAME = "admin_queries_index_main"

    # Pre-defined saved queries
    SAVED_QUERIES = {
      "active_users_count" => {
        query: "SELECT COUNT(DISTINCT users.id) FROM users INNER JOIN subscriptions ON users.id = subscriptions.user_id WHERE subscriptions.status IN (0, 3) AND subscriptions.started_at <= NOW() AND (subscriptions.expires_at IS NULL OR subscriptions.expires_at > NOW())",
        type: :count
      },
      "users_by_plan" => {
        query: "SELECT pp.name AS plan_name, COUNT(DISTINCT u.id) AS user_count FROM users u INNER JOIN subscriptions s ON u.id = s.user_id INNER JOIN pricing_plans pp ON s.pricing_plan_id = pp.id WHERE s.status IN (0, 3) GROUP BY pp.name ORDER BY user_count DESC",
        type: :results
      },
      "recent_guilds" => {
        query: "SELECT name, created_at, (SELECT COUNT(*) FROM guild_members WHERE guild_id = guilds.id) AS member_count FROM guilds WHERE created_at >= NOW() - INTERVAL '7 days' ORDER BY created_at DESC LIMIT 20",
        type: :results
      },
      "trial_users_expiring_soon" => {
        query: "SELECT u.email, u.username, s.trial_ends_at, pp.name AS plan_name FROM users u INNER JOIN subscriptions s ON u.id = s.user_id INNER JOIN pricing_plans pp ON s.pricing_plan_id = pp.id WHERE s.status = 3 AND s.trial_ends_at IS NOT NULL AND s.trial_ends_at BETWEEN NOW() AND NOW() + INTERVAL '3 days' ORDER BY s.trial_ends_at ASC",
        type: :results
      },
      "recent_admin_audit_logs" => {
        query: "SELECT created_at, admin_email, action, controller, record_type, record_id, ip_address FROM admin_audit_logs ORDER BY created_at DESC LIMIT 200",
        type: :results
      }
    }.freeze

    def index
      load_queries_index
      if request.headers["Turbo-Frame"] == QUERIES_INDEX_MAIN_FRAME
        render "queries_index_main_frame", layout: false
      end
    end

    def execute
      query_key = params[:query_key]
      custom_query = params[:custom_query]&.strip

      if custom_query.present?
        # Execute custom query (read-only for safety)
        execute_custom_query(custom_query)
      elsif query_key.present? && SAVED_QUERIES[query_key]
        # Execute saved query
        execute_saved_query(query_key)
      else
        log_admin_action(action: "query_execution_failed", changes_data: { reason: "invalid_selection" })
        invalid = I18n.t("admin.queries.invalid_selection")
        respond_to do |format|
          format.html { redirect_to admin_queries_path, alert: invalid }
          format.turbo_stream { redirect_to admin_queries_path, alert: invalid, status: :see_other }
        end
        return
      end

      @saved_queries = SAVED_QUERIES
      @query_error = nil

      respond_to do |format|
        format.html { render :index }
        format.turbo_stream { render :queries_execute_refresh }
      end
    rescue => e
      log_admin_action(
        action: "query_execution_failed",
        changes_data: {
          query_key: query_key,
          custom_query: custom_query.present?,
          error_class: e.class.name
        }
      )
      Rails.logger.error "Admin query execution error: #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}"
      @query_error = I18n.t("admin.queries.execution_error", message: e.message)
      @saved_queries = SAVED_QUERIES
      @query_results = nil
      @executed_query_key = nil
      respond_to do |format|
        format.html { render :index }
        format.turbo_stream { render :queries_execute_refresh }
      end
    end

    private

    def load_queries_index
      @saved_queries = SAVED_QUERIES
      @query_results = nil
      @query_error = nil
      @executed_query_key = nil
    end

    def execute_saved_query(query_key)
      query_def = SAVED_QUERIES[query_key]
      @executed_query_key = query_key
      
      if query_def[:type] == :count
        result = ActiveRecord::Base.connection.execute(query_def[:query])
        @query_results = { count: result.first&.values&.first || 0 }
      else
        @query_results = ActiveRecord::Base.connection.execute(query_def[:query])
      end

      row_count = @query_results.respond_to?(:count) ? @query_results.count : nil
      log_admin_action(
        action: "execute_saved_query",
        changes_data: {
          query_key: query_key,
          query_type: query_def[:type].to_s,
          row_count: row_count
        }
      )
    end

    def execute_custom_query(sql)
      # Safety check: only allow SELECT queries
      sql_upper = sql.strip.upcase
      unless sql_upper.start_with?("SELECT")
        raise ArgumentError, I18n.t("admin.queries.errors.only_select_allowed")
      end

      # Prevent dangerous operations
      dangerous_keywords = %w[DROP DELETE UPDATE INSERT ALTER CREATE TRUNCATE EXEC EXECUTE]
      if dangerous_keywords.any? { |keyword| sql_upper.include?(keyword) }
        raise ArgumentError, I18n.t("admin.queries.errors.prohibited_keywords")
      end

      @executed_query_key = "custom"
      @query_results = ActiveRecord::Base.connection.execute(sql)
      row_count = @query_results.respond_to?(:count) ? @query_results.count : nil
      log_admin_action(
        action: "execute_custom_query",
        changes_data: {
          query_hash: Digest::SHA256.hexdigest(sql),
          query_length: sql.length,
          row_count: row_count
        }
      )
    end
  end
end

