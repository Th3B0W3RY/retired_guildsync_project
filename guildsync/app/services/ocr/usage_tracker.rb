# frozen_string_literal: true

module Ocr
  class UsageTracker
    class Blocked < StandardError
      attr_reader :code, :message_key

      def initialize(code:, message:)
        @code = code
        @message_key = code
        super(message)
      end
    end

    # Message keys map to en: ocr: messages: in models.en.yml
    MESSAGES = {
      limit_reached: :limit_reached,
      hard_locked:   :hard_locked,
      trial_expired: :trial_expired,
      free_blocked:  :free_blocked,
      ip_abuse:      :ip_abuse
    }.freeze

    PLAN_LIMITS = {
      "trial" => { monthly: 3, buffer: 0 },
      "free" => { monthly: 3, buffer: 0 },
      "basic" => { monthly: 3, buffer: 0 },
      "upgraded" => { monthly: 4900, buffer: 0 },
      "elite" => { monthly: 9900, buffer: 0 }
    }.freeze

    USAGE_CACHE_PREFIX = "ocr:usage:"
    CACHE_TTL = 5.minutes

    # Max OCR requests from same IP across all users in 24h before blocking
    IP_ABUSE_THRESHOLD = 1000

    class << self
      # Returns true if user can perform one more OCR request (hard stop + IP checks).
      def can_process?(user)
        return false if user.respond_to?(:access_restricted?) && user.access_restricted?
        status, _err = check(user: user, amount: 1)
        status == :ok
      end

      # Returns [ :ok, nil ] or [ :blocked, Blocked ]
      def check(user:, amount: 1, request: nil)
        return [ :blocked, block(:hard_locked) ] if user.ocr_locked? && user.respond_to?(:ocr_hard_locked) && user.ocr_hard_locked
        return [ :ok, nil ] if user.respond_to?(:ocr_unlocked) && user.ocr_unlocked
        return [ :blocked, block(:trial_expired) ] if user.ocr_trial_expired?
        return [ :blocked, block(:free_blocked) ] if user.ocr_free? && user.ocr_monthly_limit.zero?

        plan = user.ocr_plan || "trial"
        limit_config = PLAN_LIMITS[plan] || PLAN_LIMITS["trial"]
        limit = limit_config[:monthly]
        buffer = limit_config[:buffer]
        hard_stop = limit - buffer
        used = current_usage(user)

        if used >= hard_stop
          OcrDenial.create(
            user: user,
            reason: "hard_stop_reached",
            current_usage: used,
            limit: limit,
            hard_stop: hard_stop
          )
          Rails.logger.info "OCR Usage Check - User: #{user.id}, Plan: #{plan}, Current: #{used}, Limit: #{limit}, Hard Stop: #{hard_stop} - DENIED"
          return [ :blocked, block(:limit_reached) ]
        end

        if (used + amount) > limit
          return [ :blocked, block(:limit_reached) ]
        end

        if request && !within_ip_limits?(user, request)
          return [ :blocked, block(:ip_abuse) ]
        end

        [ :ok, nil ]
      end

      def current_monthly_usage(user)
        cache_key = "#{USAGE_CACHE_PREFIX}#{user.id}:#{Time.current.strftime('%Y%m')}"
        Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
          current_usage(user)
        end
      end

      # Call after OCR has successfully completed. Optionally pass request to record IP/user_agent and check IP abuse.
      def increment_after_success!(user:, amount: 1, request: nil, initiated_by: nil)
        user.with_lock do
          ensure_month_reset!(user)
          initiated_by_id = initiated_by_id_for_row(user, initiated_by)
          amount.times do
            OcrRequest.create!(
              user: user,
              initiated_by_id: initiated_by_id,
              ip_address: request&.remote_ip,
              user_agent: request&.user_agent&.truncate(500),
              created_at: Time.current
            )
          end
          increment!(user, amount: amount)
          invalidate_usage_cache(user)
        end
      end

      # Ensures month boundary is applied, then checks and increments. Call only when about to perform OCR.
      def check_and_increment!(user:, amount: 1, request: nil, initiated_by: nil)
        user.with_lock do
          ensure_month_reset!(user)
          _, err = check(user: user, amount: amount, request: request)
          raise err if err
          initiated_by_id = initiated_by_id_for_row(user, initiated_by)
          amount.times do
            OcrRequest.create!(
              user: user,
              initiated_by_id: initiated_by_id,
              ip_address: request&.remote_ip,
              user_agent: request&.user_agent&.truncate(500),
              created_at: Time.current
            )
          end
          increment!(user, amount: amount)
          invalidate_usage_cache(user)
        end
      end

      private

      def initiated_by_id_for_row(billing_user, initiated_by)
        return nil if initiated_by.blank? || billing_user.id == initiated_by.id

        initiated_by.id
      end

      def block(key, interpolations = {})
        message = I18n.t("ocr.messages.#{key}", **interpolations, default: I18n.t("ocr.messages.limit_reached", default: key.to_s))
        Blocked.new(code: key, message: message)
      end

      def current_usage(user)
        user.respond_to?(:ocr_requests_used_this_period) ? (user.ocr_requests_used_this_period || 0) : 0
      end

      def ensure_month_reset!(user)
        return unless user.respond_to?(:ocr_last_reset_at) && user.respond_to?(:ocr_requests_used_this_period)
        # Trial/free use lifetime total; do not reset
        return if [ "trial", "free" ].include?(user.ocr_plan)

        now = Time.current
        period_start = now.beginning_of_month
        last = user.ocr_last_reset_at
        return if last.present? && last >= period_start

        user.update_columns(
          ocr_last_reset_at: period_start,
          ocr_requests_used_this_period: 0
        )
        user.reload
      end

      def increment!(user, amount: 1)
        return unless user.respond_to?(:ocr_requests_used) && user.respond_to?(:ocr_requests_used_this_period)
        user.update_columns(
          ocr_requests_used: (user.ocr_requests_used || 0) + amount,
          ocr_requests_used_this_period: (user.ocr_requests_used_this_period || 0) + amount
        )
      end

      def invalidate_usage_cache(user)
        cache_key = "#{USAGE_CACHE_PREFIX}#{user.id}:#{Time.current.strftime('%Y%m')}"
        Rails.cache.delete(cache_key)
      end

      def within_ip_limits?(user, request)
        ip = request.remote_ip
        return true if ip.blank?

        return false if AbuseFlag.for_target("IP", ip).recent.exists?

        total_from_ip = OcrRequest.where(ip_address: ip).where("created_at > ?", 24.hours.ago).count
        if total_from_ip >= IP_ABUSE_THRESHOLD
          AbuseFlag.find_or_create_by(
            target_type: "IP",
            target_value: ip,
            reason: "Excessive OCR requests across accounts: #{total_from_ip} in 24h",
            severity: 4
          )
          return false
        end
        true
      end
    end
  end
end
