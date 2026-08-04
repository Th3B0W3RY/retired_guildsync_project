# frozen_string_literal: true

class MarketingLegalPagesController < ApplicationController
  layout "application"

  skip_before_action :authenticate_user!, only: [ :show ]
  skip_before_action :require_mfa_if_enabled, only: [ :show ]

  def show
    @marketing_legal_page = MarketingLegalPage.includes(:rich_text_body).for_kind!(permitted_kind)
  end

  private

  def permitted_kind
    params[:kind].to_s.downcase
  end
end
