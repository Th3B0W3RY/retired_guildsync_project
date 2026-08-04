# frozen_string_literal: true

class AddDisasterRecoveryMarketingLegalPage < ActiveRecord::Migration[8.0]
  class MigrationMarketingLegalPage < ActiveRecord::Base
    self.table_name = "marketing_legal_pages"
  end

  class MigrationActionTextRichText < ActiveRecord::Base
    self.table_name = "action_text_rich_texts"
  end

  BODY = <<~HTML
    <div class="trix-content">
      <h2>Disaster recovery & data recovery</h2>
      <p>GuildSync is designed for operational resilience: configuration and long-form policies are stored in the production database, and routine infrastructure practices include backups and monitoring appropriate for a hosted SaaS product.</p>
      <h2>Backups &amp; retention</h2>
      <p>Backup frequency, retention windows, and restore procedures are defined by your hosting and database providers. Authorized operators should follow your organization’s runbooks for testing restores and validating recovery objectives.</p>
      <h2>User-generated content</h2>
      <p>Where soft delete is enabled, removed guild content is retained for a period to support auditing and administrative recovery. Administrators can review and restore items from the admin recovery tools when appropriate.</p>
      <h2>Contact</h2>
      <p>For operational or contractual questions about recovery commitments, use the support channels configured for your workspace.</p>
    </div>
  HTML

  def up
    return unless table_exists?(:marketing_legal_pages)
    return if MigrationMarketingLegalPage.exists?(kind: "disaster_recovery")

    max_position = MigrationMarketingLegalPage.maximum(:position)
    next_position = max_position.nil? ? 3 : max_position + 1

    page = MigrationMarketingLegalPage.create!(
      kind: "disaster_recovery",
      title: "Disaster Recovery and Data Recovery",
      position: next_position
    )

    return unless table_exists?(:action_text_rich_texts)

    MigrationActionTextRichText.create!(
      record_type: "MarketingLegalPage",
      record_id: page.id,
      name: "body",
      body: BODY
    )
  end

  def down
    return unless table_exists?(:marketing_legal_pages)

    page = MigrationMarketingLegalPage.find_by(kind: "disaster_recovery")
    return unless page

    if table_exists?(:action_text_rich_texts)
      MigrationActionTextRichText.where(
        record_type: "MarketingLegalPage",
        record_id: page.id,
        name: "body"
      ).delete_all
    end

    page.delete
  end
end
