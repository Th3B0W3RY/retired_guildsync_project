# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountCreation::ProvisionalUserBuilder do
  it "creates a user confirmed for Devise (email already verified in funnel)" do
    u = described_class.call(email: "newbie@example.com", ip_address: "127.0.0.1")

    expect(u).to be_persisted
    expect(u.confirmed_at).to be_present
    expect(u.registration_completed_at).to be_nil

    u.update!(registration_completed_at: Time.current, auth_method: :discord)
    expect(u).to be_active_for_authentication
  end
end
