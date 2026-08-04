# frozen_string_literal: true

module Ocr
  # Resolves whose OCR quota (UsageTracker counters, locks, trial state) is used for a guild stat scan.
  #
  # When the guild owner’s subscription includes +:ai_gear_scanner+, guild members’ uploads bill the
  # owner so the guild shares one paid OCR pool. Otherwise the actor is billed (their own trial/free/paid limits).
  class BillingSubject
    class << self
      def for_gear_upload(actor:, guild:)
        return actor if actor.blank? || guild.blank?

        owner = guild.owner
        return actor if owner.blank?

        unless guild.guild_members.exists?(user: actor, status: :active)
          return actor
        end

        return actor unless PlanEntitlementService.allowed?(owner, :ai_gear_scanner)

        owner
      end
    end
  end
end
