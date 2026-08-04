# frozen_string_literal: true

# Contract tests for deploy/provision.sh (nginx + Certbot bootstrap).
# Full VM E2E (SSH, sudo, DNS, Let's Encrypt) is intentionally out of CI scope.

require "rails_helper"

RSpec.describe "deploy/provision.sh (nginx + certbot)" do
  let(:provision_script) { Rails.root.join("../deploy/provision.sh") }
  let(:http_only_template) { Rails.root.join("../deploy/guildsync-nginx-http-only") }
  let(:full_nginx_template) { Rails.root.join("../deploy/guildsync-nginx") }
  let(:contents) { File.read(provision_script) }

  it "exists beside nginx templates" do
    expect(File.file?(provision_script)).to be(true), "expected #{provision_script} to exist"
    expect(File.file?(http_only_template)).to be(true), "expected #{http_only_template} to exist"
    expect(File.file?(full_nginx_template)).to be(true), "expected #{full_nginx_template} to exist"
  end

  it "installs nginx and certbot via apt" do
    expect(contents).to include("apt install -y nginx certbot")
  end

  it "prepares certbot webroot and disables default nginx site" do
    expect(contents).to include("/var/www/certbot")
    expect(contents).to match(%r{sites-enabled/default})
  end

  it "installs the guildsync vhost under sites-available and sites-enabled" do
    expect(contents).to include("/etc/nginx/sites-available/guildsync")
    expect(contents).to include("/etc/nginx/sites-enabled/guildsync")
  end

  it "uploads phase 1 and full nginx configs via scp before ssh" do
    expect(contents).to include("guildsync-nginx-http-only")
    expect(contents).to include("guildsync-nginx-full")
    expect(contents).to include('scp "${DEPLOY_SSH_ARGS[@]}"')
  end

  it "gates cert issuance on PROVISION_ISSUE_CERT and CERTBOT_EMAIL" do
    expect(contents).to include("PROVISION_ISSUE_CERT")
    expect(contents).to include("CERTBOT_EMAIL")
    expect(contents).to include("certbot certonly")
    expect(contents).to include("--webroot")
  end

  it "enables certbot renewal timer when present" do
    expect(contents).to include("certbot.timer")
  end

  it "creates maintenance dir for nginx maintenance mode" do
    expect(contents).to include("/var/www/maintenance")
  end

  it "references Let's Encrypt cert path for phase 2 gate" do
    expect(contents).to include("/etc/letsencrypt/live/guild-sync.net/fullchain.pem")
  end
end
