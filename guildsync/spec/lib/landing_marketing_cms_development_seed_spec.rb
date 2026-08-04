# frozen_string_literal: true

require "rails_helper"

RSpec.describe "landing_marketing_cms_development seed" do
  let(:seed_file) { Rails.root.join("db/seeds/landing_marketing_cms_development.rb") }

  before do
    HomepageFeatureCard.unscoped.find_each(&:destroy!)
    LandingUserFeedback.unscoped.find_each(&:destroy!)
    allow($stdout).to receive(:puts)
  end

  it "creates sample visible feedback rows when none exist" do
    load seed_file

    expect(LandingUserFeedback.count).to eq(3)
    expect(LandingUserFeedback.visible.count).to eq(3)
    expect(LandingUserFeedback.ordered.pluck(:position)).to eq([ 0, 1, 2 ])
    expect(LandingUserFeedback.ordered.first.body.to_plain_text).to include("one command center")
  end

  it "creates sample homepage feature cards when none exist" do
    load seed_file

    expect(HomepageFeatureCard.count).to eq(4)
    expect(HomepageFeatureCard.visible.count).to eq(4)
    expect(HomepageFeatureCard.ordered.pluck(:slug)).to eq(
      %w[member_management event_management automation_tools analytics_insights]
    )
    mm = HomepageFeatureCard.find_by!(slug: "member_management")
    expect(mm.body.to_plain_text).to include("Review applications")
  end

  it "does not create duplicate feedback when feedback already exists" do
    create(:homepage_feature_card)
    existing = create(:landing_user_feedback, position: 9)

    load seed_file

    expect(LandingUserFeedback.count).to eq(1)
    expect(LandingUserFeedback.first.id).to eq(existing.id)
  end

  it "does not create duplicate feature cards when a card already exists" do
    create(:landing_user_feedback)
    existing = create(:homepage_feature_card)

    load seed_file

    expect(HomepageFeatureCard.count).to eq(1)
    expect(HomepageFeatureCard.first.id).to eq(existing.id)
  end

  it "loads cleanly a second time (idempotent)" do
    load seed_file
    load seed_file

    expect(LandingUserFeedback.count).to eq(3)
    expect(HomepageFeatureCard.count).to eq(4)
  end

  it "returns early when CMS tables are missing" do
    allow(ActiveRecord::Base).to receive_message_chain(:connection, :table_exists?).and_return(false)

    expect { load seed_file }.not_to raise_error
    expect(LandingUserFeedback.count).to eq(0)
    expect(HomepageFeatureCard.count).to eq(0)
  end
end
