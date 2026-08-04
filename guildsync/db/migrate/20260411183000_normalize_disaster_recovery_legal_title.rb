# frozen_string_literal: true

class NormalizeDisasterRecoveryLegalTitle < ActiveRecord::Migration[8.0]
  class MigrationMarketingLegalPage < ActiveRecord::Base
    self.table_name = "marketing_legal_pages"
  end

  def up
    return unless table_exists?(:marketing_legal_pages)

    MigrationMarketingLegalPage.where(kind: "disaster_recovery").update_all(
      title: "Disaster Recovery and Data Recovery"
    )
  end

  def down
    return unless table_exists?(:marketing_legal_pages)

    MigrationMarketingLegalPage.where(kind: "disaster_recovery").update_all(
      title: "Disaster Recovery & Data Recovery"
    )
  end
end
