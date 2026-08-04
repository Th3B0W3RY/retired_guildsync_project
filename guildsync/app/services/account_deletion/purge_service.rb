# frozen_string_literal: true

module AccountDeletion
  # Phase A (call_soft): billing teardown and local subscription cleanup — user identity and
  # UserRestoration::Registry rows stay intact for the retention window.
  # Phase B (call_hard): destroys owned graph, tombstones User, sets account_data_purged_at.
  class PurgeService
    def initialize(user)
      @user_id = user.id
    end

    # @deprecated Use {#call_soft} or {#call_hard}. Retained as alias for hard purge (specs / ops).
    def call
      call_hard
    end

    def call_soft
      user = User.find_by(id: @user_id)
      return if user.nil?
      return if user.account_data_purged_at.present?
      return if user.account_closure_soft_completed_at.present?

      original_email = user.email
      teardown_stripe!(user)
      purge_signup_verifications!(original_email)

      user.subscriptions.find_each(&:destroy!)
      user.reload
      user.account_deletion_request&.destroy

      user.reload
      user.update_columns(
        account_closure_soft_completed_at: Time.current,
        updated_at: Time.current
      )

      Rails.logger.info("[AccountDeletion] Soft purge (Phase A) completed for user_id=#{@user_id}")
    rescue StandardError => e
      Rails.logger.error("[AccountDeletion] Soft purge failed user_id=#{@user_id}: #{e.class} #{e.message}")
      raise
    end

    def call_hard
      user = User.find_by(id: @user_id)
      return if user.nil?
      return if user.account_data_purged_at.present?

      user.subscriptions.find_each(&:destroy!)

      UserRestoration::Registry.delete_order.each do |klass|
        next if klass == User

        destroy_scope(UserRestoration::Registry.scope_for(klass, user))
      end

      user.reload
      user.account_deletion_request&.destroy

      user.avatar.purge_later if user.avatar.attached?

      user.reload
      tombstone_user!(user)
      user.reload
      user.update_columns(
        account_data_purged_at: Time.current,
        updated_at: Time.current
      )

      Rails.logger.info("[AccountDeletion] Hard purge (Phase B) completed for user_id=#{@user_id}")
    rescue StandardError => e
      Rails.logger.error("[AccountDeletion] Hard purge failed user_id=#{@user_id}: #{e.class} #{e.message}")
      raise
    end

    private

    def destroy_scope(relation)
      relation.find_each { |record| record.destroy! }
    end

    def teardown_stripe!(user)
      return if ENV["STRIPE_SECRET_KEY"].blank?

      user.subscriptions.find_each do |sub|
        next if sub.stripe_subscription_id.blank?

        stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id)
        Stripe::Subscription.cancel(stripe_sub.id)
      rescue Stripe::StripeError => e
        Rails.logger.warn("[AccountDeletion] Stripe subscription cancel #{sub.id}: #{e.message}")
      end

      return if user.stripe_customer_id.blank?

      Stripe::Customer.delete(user.stripe_customer_id)
    rescue Stripe::StripeError => e
      Rails.logger.warn("[AccountDeletion] Stripe customer delete user=#{user.id}: #{e.message}")
    end

    def purge_signup_verifications!(email)
      SignupEmailVerification.where(email: SignupEmailVerification.normalize_email(email)).delete_all
    end

    def tombstone_user!(user)
      new_password = SecureRandom.hex(32)
      encrypted_password = Devise::Encryptor.digest(User, new_password)

      user.update_columns(
        email: "deleted+#{user.id}@guildsync.invalid",
        username: "deleted_#{user.id}",
        encrypted_password: encrypted_password,
        discord_user_id: nil,
        discord_username: nil,
        discord_global_name: nil,
        discord_avatar_url: nil,
        discord_connected: false,
        confirmed_at: nil,
        confirmation_token: nil,
        confirmation_sent_at: nil,
        unconfirmed_email: nil,
        reset_password_token: nil,
        reset_password_sent_at: nil,
        remember_created_at: nil,
        locked_at: nil,
        otp_secret: nil,
        mfa_enabled: false,
        mfa_verified: false,
        auth_method: User.auth_methods[:mfa],
        stripe_customer_id: nil,
        stripe_subscription_id: nil,
        signup_ip: nil,
        last_backup_generation_ip: nil,
        updated_at: Time.current
      )
      user.reload
    end
  end
end
