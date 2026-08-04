# frozen_string_literal: true

module ApiPagination
  extend ActiveSupport::Concern

  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  private

  def paginate_relation(relation)
    page = pagination_page
    per_page = pagination_per_page
    total_count = relation.except(:limit, :offset).count
    records = relation.offset((page - 1) * per_page).limit(per_page)

    [ records, pagination_meta(page: page, per_page: per_page, total_count: total_count) ]
  end

  def paginate_array(collection)
    page = pagination_page
    per_page = pagination_per_page
    total_count = collection.length
    offset = (page - 1) * per_page
    records = collection.slice(offset, per_page) || []

    [ records, pagination_meta(page: page, per_page: per_page, total_count: total_count) ]
  end

  def pagination_meta(page:, per_page:, total_count:)
    total_pages = total_count.zero? ? 0 : (total_count.to_f / per_page).ceil

    {
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  def pagination_page
    parsed = params[:page].to_i
    parsed.positive? ? parsed : DEFAULT_PAGE
  end

  def pagination_per_page
    parsed = params[:per_page].to_i
    return DEFAULT_PER_PAGE if parsed <= 0

    [ parsed, MAX_PER_PAGE ].min
  end
end
