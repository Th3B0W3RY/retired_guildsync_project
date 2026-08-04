# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserActivity::RecordingPolicy do
  let(:user) { create(:user) }

  def request_double(method: "GET", xhr: false)
    instance_double(
      ActionDispatch::Request,
      get?: method == "GET",
      head?: method == "HEAD",
      xhr?: xhr
    )
  end

  it "records a signed-in top-level GET navigation" do
    policy = described_class.new(request: request_double, user: user)
    expect(policy.record?).to be(true)
  end

  it "does not record when no user is signed in" do
    policy = described_class.new(request: request_double, user: nil)
    expect(policy.record?).to be(false)
  end

  it "does not record non-GET requests" do
    policy = described_class.new(request: request_double(method: "POST"), user: user)
    expect(policy.record?).to be(false)
  end

  it "does not record background XHR polling" do
    policy = described_class.new(request: request_double(xhr: true), user: user)
    expect(policy.record?).to be(false)
  end
end
