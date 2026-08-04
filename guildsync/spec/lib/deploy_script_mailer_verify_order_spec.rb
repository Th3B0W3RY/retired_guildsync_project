# frozen_string_literal: true

require "rails_helper"

# The production mailer SMTP verification boots Rails (and the rolling-file logging
# initializer). It must run while Puma and Sidekiq are STOPPED so the three processes
# never race on the shared production.log daily roll (Errno::ENOENT on rename of
# production.log._copy_). These specs lock in that ordering in deploy/deploy.sh.
RSpec.describe "deploy/deploy.sh (mailer verify ordering)" do
  let(:deploy_script) { Rails.root.join("../deploy/deploy.sh") }
  let(:contents) { File.read(deploy_script) }

  it "exists" do
    expect(File.file?(deploy_script)).to be(true), "expected #{deploy_script} to exist"
  end

  it "invokes the mailer verification rake task exactly once" do
    expect(contents.scan(/verify_production_mailer_config/).size).to eq(1),
      "expected exactly one rake invocation of verify_production_mailer_config"
  end

  it "runs the mailer verification after services are stopped and before they restart" do
    stop_index    = contents.index("== Stopping services ==")
    verify_index  = contents.index("bundle exec rake guildsync:verify_production_mailer_config")
    restart_index = contents.index("== Restarting services ==")

    expect(stop_index).to be_present
    expect(verify_index).to be_present
    expect(restart_index).to be_present

    expect(verify_index).to be > stop_index
    expect(verify_index).to be < restart_index
  end
end
