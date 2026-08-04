class AddTrialWarningSentAtToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :trial_warning_sent_at, :datetime, if_not_exists: true
    add_index :subscriptions, :trial_warning_sent_at, if_not_exists: true
  end
end

