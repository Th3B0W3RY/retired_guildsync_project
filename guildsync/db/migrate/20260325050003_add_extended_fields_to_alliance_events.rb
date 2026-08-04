# frozen_string_literal: true

class AddExtendedFieldsToAllianceEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :alliance_events, :max_participants, :integer
    add_column :alliance_events, :squad_leader, :string
    add_column :alliance_events, :discord_role_mentions, :jsonb, default: []
    add_column :alliance_events, :role_categories, :jsonb, default: [ "dps", "tank", "healer", "ranged" ]
  end
end
