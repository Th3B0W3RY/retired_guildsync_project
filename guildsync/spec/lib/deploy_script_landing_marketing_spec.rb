# frozen_string_literal: true

require "rails_helper"

RSpec.describe "deploy/deploy.sh (landing marketing)" do
  let(:deploy_script) { Rails.root.join("../deploy/deploy.sh") }

  it "does not run landing_marketing:import on deploy (production DB is CMS source of truth)" do
    expect(File.file?(deploy_script)).to be(true), "expected #{deploy_script} to exist"
    contents = File.read(deploy_script)
    expect(contents).not_to include("landing_marketing:import")
  end
end
