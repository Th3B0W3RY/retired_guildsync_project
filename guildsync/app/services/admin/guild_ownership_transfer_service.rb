# frozen_string_literal: true

module Admin
  # Performs admin-initiated guild ownership change and optionally runs
  # {SubscriptionCancellationService} for the previous owner when they have
  # zero active owned guilds after the transfer (same rules as self-serve billing).
  class GuildOwnershipTransferService
    TransferResult = Data.define(:old_owner, :billing_outcome, :billing_error, :billing_mode)

    def self.call(guild:, new_owner:, cancel_previous_owner_billing: false)
      old_owner = guild.owner
      guild.update!(owner: new_owner)

      unless cancel_previous_owner_billing
        return TransferResult.new(
          old_owner: old_owner,
          billing_outcome: :not_requested,
          billing_error: nil,
          billing_mode: nil
        )
      end

      old_owner.reload
      if old_owner.active_owned_guilds_count.positive?
        return TransferResult.new(
          old_owner: old_owner,
          billing_outcome: :skipped_still_owns_guilds,
          billing_error: nil,
          billing_mode: nil
        )
      end

      sub_result = SubscriptionCancellationService.call(user: old_owner)
      if sub_result.ok
        TransferResult.new(
          old_owner: old_owner,
          billing_outcome: :applied,
          billing_error: nil,
          billing_mode: sub_result.mode
        )
      elsif sub_result.error == "No subscription to cancel."
        TransferResult.new(
          old_owner: old_owner,
          billing_outcome: :no_subscription,
          billing_error: nil,
          billing_mode: nil
        )
      else
        TransferResult.new(
          old_owner: old_owner,
          billing_outcome: :failed,
          billing_error: sub_result.error,
          billing_mode: nil
        )
      end
    end
  end
end
