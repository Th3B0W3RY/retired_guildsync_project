class BackfillDiscordLimitsOnPricingPlans < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Backfilling Discord feature limits by pricing plan" do
      execute <<~SQL
        UPDATE pricing_plans
        SET
          max_polls = COALESCE(max_polls,
            CASE name
              WHEN 'Free' THEN 3
              WHEN 'Basic' THEN 25
              WHEN 'Upgraded' THEN 100
              ELSE 25
            END
          ),
          max_loot_rolls = COALESCE(max_loot_rolls,
            CASE name
              WHEN 'Free' THEN 2
              WHEN 'Basic' THEN 20
              WHEN 'Upgraded' THEN 80
              ELSE 20
            END
          ),
          max_events = COALESCE(max_events,
            CASE name
              WHEN 'Free' THEN 3
              WHEN 'Basic' THEN 25
              WHEN 'Upgraded' THEN 100
              ELSE 25
            END
          )
        WHERE name <> 'Elite';
      SQL
    end
  end

  def down
    # Non-reversible data migration. Leave values as-is.
  end
end
