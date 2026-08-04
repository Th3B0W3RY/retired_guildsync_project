# frozen_string_literal: true

module Admin
  class FontawesomeFreeIconsController < BaseController
    def index
      icons = FontawesomeFreeIcon.ordered.pluck(:style, :icon_name, :label)
      render json: { icons: icons }
    end
  end
end
