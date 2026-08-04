# frozen_string_literal: true

class CreateMarketingLegalPages < ActiveRecord::Migration[8.0]
  class MigrationMarketingLegalPage < ApplicationRecord
    self.table_name = "marketing_legal_pages"
  end

  class MigrationActionTextRichText < ApplicationRecord
    self.table_name = "action_text_rich_texts"
  end

  LEGAL_PAGE_SEEDS = [
    {
      kind: "privacy",
      title: "Privacy Policy",
      body: <<~HTML
        <div class="trix-content">
          <h2>Overview</h2>
          <p>GuildSync only stores the account, billing, and community-management data required to operate the service. We do not sell customer data, and administrative access to production systems is restricted to authorized operators.</p>
          <h2>What We Store</h2>
          <p>Stored data can include account identifiers, guild configuration, billing metadata, uploaded content, and audit trails required for security and support.</p>
          <h2>Retention</h2>
          <p>We retain data for as long as it is needed to provide the service, comply with legal obligations, and preserve security or billing records. Admins can update this page at any time from the marketing CMS.</p>
        </div>
      HTML
    },
    {
      kind: "terms",
      title: "Terms of Service",
      body: <<~HTML
        <div class="trix-content">
          <h2>Use of Service</h2>
          <p>GuildSync provides hosted tooling for guild and community operations. You agree to use the service lawfully and not to abuse, disrupt, or attempt to bypass service controls.</p>
          <h2>Accounts and Billing</h2>
          <p>Account owners are responsible for the accuracy of billing information, authorized access to their workspace, and compliance with any plan limits or community rules.</p>
          <h2>Changes</h2>
          <p>GuildSync may update service functionality over time. Material legal or policy changes should be reflected on this page by an authorized administrator before release.</p>
        </div>
      HTML
    },
    {
      kind: "security",
      title: "Security",
      body: <<~HTML
        <div class="trix-content">
          <h2>Security Posture</h2>
          <p>GuildSync uses authenticated admin access, database-backed audit logging, and infrastructure controls appropriate for a hosted SaaS application.</p>
          <h2>Operational Controls</h2>
          <p>Backups, monitoring, and error reporting are managed through production infrastructure and admin tooling. Sensitive configuration is stored outside Git and should be rotated through approved operational procedures.</p>
          <h2>Reporting</h2>
          <p>If you discover a potential security issue, contact the GuildSync team through the support channels configured by the administrators.</p>
        </div>
      HTML
    }
  ].freeze

  def up
    create_table :marketing_legal_pages do |t|
      t.string :kind, null: false
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :marketing_legal_pages, :kind, unique: true
    add_index :marketing_legal_pages, :position, unique: true

    return unless table_exists?(:action_text_rich_texts)

    LEGAL_PAGE_SEEDS.each_with_index do |attrs, index|
      page = MigrationMarketingLegalPage.create!(
        kind: attrs[:kind],
        title: attrs[:title],
        position: index
      )

      MigrationActionTextRichText.create!(
        record_type: "MarketingLegalPage",
        record_id: page.id,
        name: "body",
        body: attrs[:body]
      )
    end
  end

  def down
    if table_exists?(:action_text_rich_texts)
      MigrationActionTextRichText.where(record_type: "MarketingLegalPage", name: "body").delete_all
    end

    drop_table :marketing_legal_pages, if_exists: true
  end
end
