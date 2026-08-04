# frozen_string_literal: true

# Idempotent sample rows for local QA of the guest landing (carousel + feature grid + /features/:slug).
# Loaded from db/seeds.rb in development only.

cms_tables_missing =
  !ActiveRecord::Base.connection.table_exists?("landing_user_feedbacks") ||
  !ActiveRecord::Base.connection.table_exists?("homepage_feature_cards")

if cms_tables_missing
  puts "  Landing marketing CMS samples: skipped (marketing CMS tables missing — run migrations)."
  return
end

if LandingUserFeedback.exists?
  puts "  Landing user feedback samples: skipped (#{LandingUserFeedback.count} row(s) already present)."
else
  samples = [
    "<p>GuildSync gave our officers <strong>one command center</strong> instead of five spreadsheets.</p>",
    "<p>Recruiting, events, and docs finally live in the same workflow.</p>",
    "<p>Our members actually use the roadmap and release notes—huge win.</p>",
  ]
  samples.each_with_index do |html, idx|
    record = LandingUserFeedback.new(visible: true, position: idx)
    record.body = html
    record.save!
  end
  puts "  Landing user feedback samples: created #{LandingUserFeedback.count} entr(y|ies)."
end

if HomepageFeatureCard.exists?
  puts "  Homepage feature card samples: skipped (#{HomepageFeatureCard.count} row(s) already present)."
else
  demo_cards = [
    {
      slug: "member_management",
      title: "Member management",
      description: "Rosters, applications, and tags in one guild-aware workflow.",
      icon_key: "member_management",
      body: "<p>Review applications, track invites, and keep officer notes where your roster already lives.</p>",
    },
    {
      slug: "event_management",
      title: "Event management",
      description: "Schedule runs, reminders, and signups without losing people in chat scrollback.",
      icon_key: "event_management",
      body: "<p>Put events on the calendar, sync expectations in-thread, and see who is actually coming.</p>",
    },
    {
      slug: "automation_tools",
      title: "Automation tools",
      description: "Cut manual toil for recurring officer tasks.",
      icon_key: "automation_tools",
      body: "<p>Automate the boring parts so leaders spend time on people, not copy-paste.</p>",
    },
    {
      slug: "analytics_insights",
      title: "Analytics & insights",
      description: "See participation trends instead of guessing from vibes.",
      icon_key: "analytics_insights",
      body: "<p>Understand engagement over time and spot drop-off before it becomes drama.</p>",
    },
  ]
  demo_cards.each_with_index do |attrs, idx|
    HomepageFeatureCard.create!(attrs.merge(visible: true, position: idx))
  end
  puts "  Homepage feature card samples: created #{HomepageFeatureCard.count} card(s)."
end
