# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discord::OAuthPrimarySession do
  describe ".apply!" do
    let(:user) { create(:user, auth_method: "discord", discord_user_id: "111222333") }
    let(:session) { {} }
    let(:warden) { instance_double("Warden::Proxy", user: nil) }
    let(:controller) do
      instance_double("ApplicationController", session: session, warden: warden)
    end

    before do
      allow(controller).to receive(:sign_in)
      allow(warden).to receive(:set_user)
    end

    it "raises when the user is blank" do
      expect { described_class.apply!(controller, nil) }.to raise_error(ArgumentError)
    end

    it "signs the user in and satisfies the session MFA gate" do
      described_class.apply!(controller, user)

      expect(controller).to have_received(:sign_in).with(user, event: :authentication)
      expect(session[:user_id]).to eq(user.id)
      expect(session[:mfa_verified]).to be(true)
      expect(session[:mfa_verified_at]).to be_present
      expect(session[:just_logged_in]).to be(true)
      expect(warden).to have_received(:set_user).with(user, scope: :user)
    end
  end
end
