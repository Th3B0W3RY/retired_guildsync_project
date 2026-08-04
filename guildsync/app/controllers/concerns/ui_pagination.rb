# frozen_string_literal: true

# Server-rendered HTML pagination (page / per_page query params).
module UiPagination
  extend ActiveSupport::Concern

  private

  def ui_paginate(scope, per_page:, max_per_page: 100, page_key: :page)
    page = ui_page_param(page_key)
    per = ui_per_page_param(default: per_page, max: max_per_page)
    total = scope.count
    records = scope.offset((page - 1) * per).limit(per)
    [ records, ui_pagination_hash(page: page, per_page: per, total_count: total) ]
  end

  def ui_page_param(key = :page)
    p = params[key].to_i
    p.positive? ? p : 1
  end

  def ui_per_page_param(default:, max:)
    n = params[:per_page].to_i
    n = default if n <= 0
    [ n, max ].min
  end

  def ui_pagination_hash(page:, per_page:, total_count:)
    total_pages = total_count.zero? ? 0 : (total_count.to_f / per_page).ceil
    { page: page, per_page: per_page, total_count: total_count, total_pages: total_pages }
  end
end
