# frozen_string_literal: true

require "rails_helper"

RSpec.describe FontawesomeFreeIconsSyncJob, type: :job do
  it "runs the sync service" do
    stub_request(:get, %r{cdn\.jsdelivr\.net/gh/FortAwesome/Font-Awesome@6/metadata/icons\.json})
      .to_return(status: 200, body: { "a" => { "free" => [ "solid" ], "label" => "A" } }.to_json, headers: { "Content-Type" => "application/json" })

    described_class.perform_now

    expect(FontawesomeFreeIcon.find_by(style: "solid", icon_name: "a")).to be_present
  end
end
