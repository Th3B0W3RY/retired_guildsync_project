# frozen_string_literal: true

module Admin
  class MarketingLegalPagesController < BaseController
    before_action :set_marketing_legal_page

    def edit; end

    def update
      if @marketing_legal_page.update(admin_params)
        AdminAuditLog.log_action(
          admin_email: current_admin_email,
          action: "update_marketing_legal_page",
          controller: "marketing_legal_pages",
          record: @marketing_legal_page,
          changes_data: { kind: @marketing_legal_page.kind, title: @marketing_legal_page.title }
        )
        redirect_to admin_homepage_footer_settings_path,
                    notice: "#{@marketing_legal_page.title} page updated."
      else
        flash.now[:alert] = @marketing_legal_page.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_marketing_legal_page
      @marketing_legal_page = MarketingLegalPage.with_rich_text_body.for_kind!(params[:id])
    end

    def admin_params
      params.require(:marketing_legal_page).permit(:title, :body)
    end
  end
end
