# frozen_string_literal: true

class KeepOneActiveBackupCodePerUser < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      WITH ranked_backup_codes AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY user_id
                 ORDER BY generated_at DESC, id DESC
               ) AS row_number
        FROM backup_codes
        WHERE active = TRUE AND used = FALSE
      )
      UPDATE backup_codes
      SET active = FALSE,
          invalidated_at = COALESCE(invalidated_at, NOW()),
          invalidated_reason = 'single_backup_code_policy'
      FROM ranked_backup_codes
      WHERE backup_codes.id = ranked_backup_codes.id
        AND ranked_backup_codes.row_number > 1
    SQL
  end

  def down
    # Historical backup codes cannot be safely reactivated because some may have
    # been superseded or exposed under the newer one-code policy.
  end
end
