# frozen_string_literal: true

module Admin
  class ContentModerationController < BaseController
    MODERATABLE_TYPES = %w[FeatureRequest FeatureRequestComment].freeze
    MODERATABLE_CLASS_MAP = {
      "FeatureRequest" => FeatureRequest,
      "FeatureRequestComment" => FeatureRequestComment
    }.freeze
    CONTENT_MODERATION_INDEX_MAIN_FRAME = "admin_content_moderation_index_main"

    def index
      @tab = params[:tab].presence || "pending"
      begin
        load_index_data
      rescue StandardError => e
        Rails.logger.error("[ContentModeration] index failed: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        set_safe_index_defaults
        flash.now[:alert] = I18n.t("admin.content_moderation.flash.index_load_error")
      end
      return render("content_moderation_index_frame", layout: false) if request.headers["Turbo-Frame"] == CONTENT_MODERATION_INDEX_MAIN_FRAME
    end

    def approve
      content = moderatable_content_or_respond
      return unless content

      content.update!(
        moderation_status: "approved",
        moderation_reviewed_at: Time.current,
        moderation_reason: nil,
        moderation_notes: params[:moderation_notes]
      )
      ModerationAuditLog.log!(admin_email: current_admin_email, action: "approve", content_type: content.class.name, content_id: content.id, notes: params[:moderation_notes])
      log_admin_action(action: "approve_content", record: content)
      reload_pending_moderation_assigns
      @content_moderation_flash_message = I18n.t("admin.content_moderation.flash.approve")
      @content_moderation_flash_variant = :notice
      respond_moderation_success
    end

    def hide
      content = moderatable_content_or_respond
      return unless content

      content.update!(
        moderation_status: "rejected",
        moderation_reviewed_at: Time.current,
        moderation_reason: params[:moderation_reason].presence || "Hidden by moderator",
        moderation_notes: params[:moderation_notes]
      )
      ModerationAuditLog.log!(admin_email: current_admin_email, action: "reject", content_type: content.class.name, content_id: content.id, notes: params[:moderation_notes])
      log_admin_action(action: "hide_content", record: content)
      reload_pending_moderation_assigns
      @content_moderation_flash_message = I18n.t("admin.content_moderation.flash.hide")
      @content_moderation_flash_variant = :notice
      respond_moderation_success
    end

    def soft_delete
      content = moderatable_content_or_respond
      return unless content

      if content.respond_to?(:soft_delete!)
        content.soft_delete!
      elsif content.respond_to?(:update!) && content.respond_to?(:deleted_at=)
        content.update!(deleted_at: Time.current)
      end
      ModerationAuditLog.log!(admin_email: current_admin_email, action: "soft_delete", content_type: content.class.name, content_id: content.id)
      log_admin_action(action: "soft_delete_content", record: content)
      reload_pending_moderation_assigns
      @content_moderation_flash_message = I18n.t("admin.content_moderation.flash.soft_delete")
      @content_moderation_flash_variant = :notice
      respond_moderation_success
    end

    def add_blocked_word
      word = params[:word].to_s.strip.downcase
      if word.blank?
        respond_blocked_words(:alert, I18n.t("admin.content_moderation.flash.word_blank"))
        return
      end
      if BlockedWord.exists?(word: word)
        respond_blocked_words(:alert, I18n.t("admin.content_moderation.flash.word_duplicate"))
        return
      end
      BlockedWord.create!(word: word, category: params[:category].presence || "profanity")
      BlockedContentFilter.reset!
      respond_blocked_words(:notice, I18n.t("admin.content_moderation.flash.word_added"))
    end

    def remove_blocked_word
      bw = BlockedWord.find_by(id: params[:id])
      if bw
        bw.destroy!
        BlockedContentFilter.reset!
        respond_blocked_words(:notice, I18n.t("admin.content_moderation.flash.word_removed"))
      else
        respond_blocked_words(:alert, I18n.t("admin.content_moderation.flash.word_not_found"))
      end
    end

    def run_health_check
      ContentModerationHealthCheckJob.perform_async
      respond_health_tab(:notice, I18n.t("admin.content_moderation.flash.health_queued"))
    end

    def trigger_profanity_update
      ProfanityListUpdateJob.perform_async
      respond_profanity_tab(:notice, I18n.t("admin.content_moderation.flash.profanity_update_queued"))
    end

    private

    def resolve_moderatable_content
      type = params[:content_type].to_s
      return [nil, :invalid_content_type] unless MODERATABLE_TYPES.include?(type)

      id = params[:content_id]
      return [nil, :invalid_content_id] unless id.to_s.match?(/\A\d+\z/)

      [MODERATABLE_CLASS_MAP.fetch(type).find(id), nil]
    rescue ActiveRecord::RecordNotFound
      [nil, :content_not_found]
    end

    def moderatable_content_or_respond
      content, error_key = resolve_moderatable_content
      if error_key
        respond_moderation_failure(error_key)
        return nil
      end
      content
    end

    def reload_pending_moderation_assigns
      @pending_requests = FeatureRequest.pending_review.order(moderation_flagged_at: :desc)
      @pending_comments = FeatureRequestComment.pending_review.order(moderation_flagged_at: :desc)
      @pending_count = @pending_requests.count + @pending_comments.count
    end

    def respond_moderation_failure(error_key)
      message = I18n.t("admin.content_moderation.flash.#{error_key}")
      reload_pending_moderation_assigns
      @content_moderation_flash_message = message
      @content_moderation_flash_variant = :alert
      respond_to do |format|
        format.html { redirect_back(fallback_location: admin_content_moderation_index_path, alert: message) }
        format.turbo_stream { render :content_moderation_refresh }
      end
    end

    def respond_moderation_success
      respond_to do |format|
        format.html { redirect_back(fallback_location: admin_content_moderation_index_path, notice: @content_moderation_flash_message) }
        format.turbo_stream { render :content_moderation_refresh }
      end
    end

    def respond_blocked_words(variant, message)
      @blocked_words = BlockedWord.order(:word)
      @content_moderation_flash_message = message
      @content_moderation_flash_variant = variant
      respond_to do |format|
        format.html do
          opts = { fallback_location: admin_content_moderation_index_path(tab: "blocked_words") }
          opts[variant == :notice ? :notice : :alert] = message
          redirect_back(**opts)
        end
        format.turbo_stream { render :content_moderation_blocked_words_refresh }
      end
    end

    def reload_profanity_tab_assigns
      @profanity_logs = ProfanityUpdateLog.recent
      @profanity_health = ProfanityUpdateLog.health_status
      @blocked_words_count = BlockedWord.active.count
      @last_profanity_run = ProfanityUpdateLog.recent.first
    end

    def reload_health_assigns
      @last_health = ModerationHealthCheck.last_health_status
      @health_score = ModerationHealthCheck.health_score
    end

    def respond_profanity_tab(variant, message)
      reload_profanity_tab_assigns
      @content_moderation_flash_message = message
      @content_moderation_flash_variant = variant
      respond_to do |format|
        format.html do
          opts = { fallback_location: admin_content_moderation_index_path(tab: "profanity_list") }
          opts[variant == :notice ? :notice : :alert] = message
          redirect_back(**opts)
        end
        format.turbo_stream { render :content_moderation_profanity_refresh }
      end
    end

    def respond_health_tab(variant, message)
      reload_health_assigns
      @content_moderation_flash_message = message
      @content_moderation_flash_variant = variant
      respond_to do |format|
        format.html do
          opts = { fallback_location: admin_content_moderation_index_path(tab: "health") }
          opts[variant == :notice ? :notice : :alert] = message
          redirect_back(**opts)
        end
        format.turbo_stream { render :content_moderation_health_refresh }
      end
    end

    def load_index_data
      reload_pending_moderation_assigns
      @blocked_words = BlockedWord.order(:word)
      @moderation_audit_logs = ModerationAuditLog.recent.limit(50)
      @last_health = ModerationHealthCheck.last_health_status
      @health_score = ModerationHealthCheck.health_score
      @stats_7d = stats_since(7.days.ago)
      @stats_30d = stats_since(30.days.ago)
      @profanity_logs = ProfanityUpdateLog.recent
      @profanity_health = ProfanityUpdateLog.health_status
      @blocked_words_count = BlockedWord.active.count
      @last_profanity_run = ProfanityUpdateLog.recent.first
    end

    def set_safe_index_defaults
      @pending_requests = []
      @pending_comments = []
      @pending_count = 0
      @blocked_words = []
      @moderation_audit_logs = []
      @last_health = nil
      @health_score = 0
      @stats_7d = { flagged: 0, approved: 0, rejected: 0 }
      @stats_30d = { flagged: 0, approved: 0, rejected: 0 }
      @profanity_logs = []
      @profanity_health = { status: "unknown" }
      @blocked_words_count = 0
      @last_profanity_run = nil
    end

    def stats_since(since)
      {
        flagged: FeatureRequest.with_deleted.where("moderation_flagged_at >= ?", since).count + FeatureRequestComment.with_deleted.where("moderation_flagged_at >= ?", since).count,
        approved: FeatureRequest.with_deleted.where(moderation_status: "approved").where("moderation_reviewed_at >= ?", since).count + FeatureRequestComment.with_deleted.where(moderation_status: "approved").where("moderation_reviewed_at >= ?", since).count,
        rejected: FeatureRequest.with_deleted.where(moderation_status: "rejected").where("moderation_reviewed_at >= ?", since).count + FeatureRequestComment.with_deleted.where(moderation_status: "rejected").where("moderation_reviewed_at >= ?", since).count
      }
    end
  end
end
