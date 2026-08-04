# frozen_string_literal: true

module AccountClosure
  # Restores a self-closed account during the retention window (before hard purge).
  # Reverses archive + closure timestamps only; guild/content rows are preserved by design.
  class AdminRestore
    Result = Struct.new(:ok?, :error_key, keyword_init: true)

    def self.eligible?(user)
      return false if user.nil?
      return false if user.account_data_purged_at.present?
      return false unless user.account_closed_at.present?

      user.account_closed_at >= SoftDeletable::RETENTION_PERIOD.ago
    end

    def self.ineligible_reason(user)
      return :not_applicable if user.nil?
      return :hard_purged if user.account_data_purged_at.present?
      return :not_applicable if user.account_closed_at.blank?
      return :outside_retention if user.account_closed_at < SoftDeletable::RETENTION_PERIOD.ago

      nil
    end

    def initialize(user)
      @user = user
    end

    def call
      unless self.class.eligible?(@user)
        key = self.class.ineligible_reason(@user) || :not_applicable
        return Result.new(ok?: false, error_key: key)
      end

      @user.update_columns(
        archived: false,
        account_closed_at: nil,
        account_deletion_started_at: nil,
        account_closure_soft_completed_at: nil,
        updated_at: Time.current
      )

      Result.new(ok?: true, error_key: nil)
    end
  end
end
