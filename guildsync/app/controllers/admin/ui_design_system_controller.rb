# frozen_string_literal: true

module Admin
  class UiDesignSystemController < BaseController
    UI_DESIGN_SYSTEM_MAIN_FRAME = "admin_ui_design_system_main"

    def show
      return render("ui_design_system_show_frame", layout: false) if request.headers["Turbo-Frame"] == UI_DESIGN_SYSTEM_MAIN_FRAME
    end
  end
end
