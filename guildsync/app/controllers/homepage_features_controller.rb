# frozen_string_literal: true

class HomepageFeaturesController < ApplicationController
  layout "application"

  skip_before_action :authenticate_user!, only: [ :show ]
  skip_before_action :require_mfa_if_enabled, only: [ :show ]

  def show
    @homepage_feature_card = HomepageFeatureCard.visible.with_rich_text_body.find_by!(slug: permitted_slug)
  end

  private

  def permitted_slug
    params[:slug].to_s.downcase
  end
end
