# frozen_string_literal: true

# Landing marketing CMS — optional YAML backup / recovery only.
#
# Source of truth in production: the database (Admin → Homepage & guest marketing).
# Deploy does NOT run import; admin edits persist across deploys.
#
# Manual tooling:
#   - landing_marketing:export — dump feature cards + compare tables to YAML (development/test only).
#   - landing_marketing:import — destructive replace from marketing_snapshot.yml. In production,
#     requires FORCE_LANDING_MARKETING_IMPORT=1 or the task aborts.
#   - landing_marketing:write_baseline — regenerate the YAML file from i18n + Catalog (no DB).
#
namespace :landing_marketing do
  desc "Write config/landing/marketing_snapshot.yml from the current DB (development/test only)"
  task export: :environment do
    unless Rails.env.development? || Rails.env.test?
      abort "landing_marketing:export is only allowed in development or test (refusing #{Rails.env})."
    end

    path = LandingMarketing::Snapshot::Exporter.new.call
    puts "Wrote #{path}"
  end

  desc "Replace homepage feature cards + landing comparison tables from config/landing/marketing_snapshot.yml " \
       "(production: set FORCE_LANDING_MARKETING_IMPORT=1)"
  task import: :environment do
    LandingMarketing::Snapshot::Importer.new.call
    puts "Imported landing marketing snapshot (#{HomepageFeatureCard.count} cards, #{LandingComparisonTable.count} tables)."
  rescue LandingMarketing::Snapshot::Importer::Error => e
    abort e.message
  end

  desc "Regenerate marketing_snapshot.yml from i18n + Catalog baseline (no DB reads; overwrites file)"
  task write_baseline: :environment do
    path = LandingMarketing::Snapshot::Paths.default_file
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, LandingMarketing::Snapshot::Baseline.to_yaml)
    puts "Wrote baseline snapshot to #{path}"
  end
end
