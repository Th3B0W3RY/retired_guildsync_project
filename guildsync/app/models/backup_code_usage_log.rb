# frozen_string_literal: true

class BackupCodeUsageLog < ApplicationRecord
  belongs_to :user
  belongs_to :backup_code, optional: true
end
